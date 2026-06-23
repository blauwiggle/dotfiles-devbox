#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# ado-sync.sh — Azure DevOps repo sync (organisation-agnostic)
#
# Clones missing repos, pulls main/master, fetches other branches, and writes a
# REPOS.md index at the workspace root. The Azure DevOps organisation URL, the
# local basepath, and the project selection are stored in ~/.ado-sync.conf, which
# is created on first run (and is intentionally NOT committed to any repo).
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────────────────
readonly CONFIG_FILE="$HOME/.ado-sync.conf"
readonly PAT_DOCS="https://learn.microsoft.com/en-us/azure/devops/cli/log-in-via-pat?view=azure-devops&tabs=linux"

# Repo index / entrypoint files written at the workspace root (BASEPATH)
readonly INDEX_FILE="REPOS.md"
readonly ENTRYPOINT_FILE="CLAUDE.md"

# ANSI colours
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# Runtime state (populated by load_config / select_projects)
ORG_URL=""
BASEPATH=""
SELECTED_PROJECTS=""
RESELECT=false
USE_SSH=true    # prefer SSH URLs; override with --https

# Summary tracking
declare -a CLONED=() PULLED=() FETCHED=() SKIPPED=() DELETED=() FAILED=()

# ──────────────────────────────────────────────────────────────────────────────
# Logging helpers
# ──────────────────────────────────────────────────────────────────────────────
info()    { echo -e "  ${CYAN}${BOLD}[INFO]${NC}  $*"; }
ok()      { echo -e "  ${GREEN}${BOLD}[ OK ]${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}${BOLD}[WARN]${NC}  $*"; }
err()     { echo -e "  ${RED}${BOLD}[ERR ]${NC}  $*" >&2; }
section() { echo -e "\n${BOLD}=== $* ===${NC}"; }

# ──────────────────────────────────────────────────────────────────────────────
# Banner (shown on every run, after config is loaded)
# ──────────────────────────────────────────────────────────────────────────────
print_banner() {
  echo -e "\n${BOLD}  ╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}  ║        Azure DevOps Repo Sync            ║${NC}"
  echo -e "${BOLD}  ╚══════════════════════════════════════════╝${NC}"
  echo -e "  ${DIM}Organisation : ${ORG_URL}${NC}"
  echo -e "  ${DIM}Config file  : ${CONFIG_FILE}${NC}"
  echo ""
  echo -e "  ${DIM}Available options:${NC}"
  echo -e "  ${DIM}  -r, --reselect              Re-open project selection${NC}"
  echo -e "  ${DIM}  --https                     Use HTTPS URLs instead of SSH${NC}"
  echo -e "  ${DIM}  -h, --help                  Show full usage help${NC}"
  echo -e "  ${DIM}  AZURE_DEVOPS_EXT_PAT=<pat>  PAT fallback if 'az login' is not active${NC}"
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
#
# On first run (no config file) the user is prompted for:
#   1. the Azure DevOps organisation URL (e.g. https://dev.azure.com/<org>/)
#   2. the local basepath where repos are stored
# These — plus the later project selection — are written to ~/.ado-sync.conf.
# The config file is never committed; the script recreates it on a fresh machine.
# ──────────────────────────────────────────────────────────────────────────────

# Normalise an org URL: trim whitespace, ensure a single trailing slash.
normalise_org_url() {
  local url="$1"
  url="${url#"${url%%[![:space:]]*}"}"   # ltrim
  url="${url%"${url##*[![:space:]]}"}"    # rtrim
  [[ -z "$url" ]] && { printf '%s' ""; return; }
  url="${url%/}/"                          # exactly one trailing slash
  printf '%s' "$url"
}

# Convert an ADO HTTPS remote URL to SSH format.
# https://dev.azure.com/<org>/<project>/_git/<repo>  →  git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
# Falls back to the original URL if it doesn't match the expected pattern.
to_ssh_url() {
  local url="$1"
  if [[ "$url" =~ ^https://dev\.azure\.com/([^/]+)/([^/]+)/_git/(.+)$ ]]; then
    echo "git@ssh.dev.azure.com:v3/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
  else
    echo "$url"
  fi
}

prompt_org_url() {
  local input=""
  while [[ -z "$input" ]]; do
    echo "  Azure DevOps organisation URL"
    echo -e "  ${DIM}e.g. https://dev.azure.com/<your-org>/  (or your TFS/Server collection URL)${NC}"
    printf "  Org URL: "
    read -r input
    input="$(normalise_org_url "$input")"
    if [[ "$input" != https://* && "$input" != http://* ]]; then
      warn "URL must start with http:// or https:// — try again."
      input=""
    fi
  done
  ORG_URL="$input"
}

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    section "First-time setup"
    prompt_org_url
    echo ""
    echo "  Where should repos be stored locally?"
    printf "  Basepath [%s]: " "$PWD"
    read -r input_path
    BASEPATH="${input_path:-$PWD}"
    BASEPATH="${BASEPATH/#\~/$HOME}"   # expand leading ~ if typed
    mkdir -p "$BASEPATH"
    SELECTED_PROJECTS=""
    save_config
    echo ""
    info "Config saved → ${CONFIG_FILE}"
    echo "    You can edit this file at any time to change ORG_URL, BASEPATH or SELECTED_PROJECTS."
    echo ""
  else
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    ORG_URL="$(normalise_org_url "${ORG_URL:-}")"
    if [[ -z "$ORG_URL" ]]; then
      warn "No ORG_URL in ${CONFIG_FILE} — prompting."
      prompt_org_url
      save_config
    fi
  fi
  # Export stored PAT so az devops commands use it without prompting.
  # Note: keep this in an if-block (not `[[ ]] && ...`) — a trailing test that
  # returns non-zero would become load_config's exit status and, under set -e,
  # silently kill the whole script.
  if [[ -n "${PAT:-}" ]]; then
    export AZURE_DEVOPS_EXT_PAT="$PAT"
  fi
}

save_config() {
  cat > "$CONFIG_FILE" <<EOF
# ado-sync configuration — edit freely (NOT version-controlled)
ORG_URL="${ORG_URL}"
BASEPATH="${BASEPATH}"
SELECTED_PROJECTS="${SELECTED_PROJECTS}"
PAT="${PAT:-}"
EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Prerequisites
# ──────────────────────────────────────────────────────────────────────────────
check_prerequisites() {
  section "Checking prerequisites"

  # az CLI
  if ! command -v az &>/dev/null; then
    err "az CLI not found."
    echo "    Linux : curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    echo "    macOS : brew install azure-cli"
    echo "    Docs  : https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
  fi
  ok "az CLI $(az version --query '"azure-cli"' -o tsv)"

  # jq (required for reliable JSON parsing of repo lists)
  if ! command -v jq &>/dev/null; then
    err "jq not found."
    echo "    Linux : sudo apt install jq"
    echo "    macOS : brew install jq"
    exit 1
  fi
  ok "jq $(jq --version)"

  # azure-devops extension
  if ! az extension show --name azure-devops &>/dev/null; then
    info "Installing azure-devops extension..."
    az extension add --name azure-devops
  fi
  ok "azure-devops extension ready"

  # Login / connectivity — prompt for PAT rather than falling into az device code flow
  if ! az devops project list --org "$ORG_URL" --top 1 -o none 2>/dev/null; then
    warn "Not authenticated to ${ORG_URL} — enter a Personal Access Token."
    echo ""
    echo "    Create one at: ${ORG_URL}_usersSettings/tokens"
    echo "    Required scopes: Code (Read), Project and Team (Read)"
    echo ""
    printf "    PAT (input hidden): "
    read -rs PAT
    echo ""
    if [[ -z "$PAT" ]]; then
      err "No PAT provided — cannot continue."
      echo "    Docs: ${PAT_DOCS}"
      exit 1
    fi
    export AZURE_DEVOPS_EXT_PAT="$PAT"
    save_config
    if ! az devops project list --org "$ORG_URL" --top 1 -o none 2>/dev/null; then
      err "PAT rejected by ${ORG_URL} — check scopes and expiry."
      echo "    Docs: ${PAT_DOCS}"
      exit 1
    fi
  fi
  ok "Connected to ${ORG_URL}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Git authentication
# Priority:
#   1. An already-configured git credential helper (e.g. git-credential-manager)
#   2. Azure AD token via 'az account get-access-token'
#   3. AZURE_DEVOPS_EXT_PAT environment variable
#   4. Interactive PAT prompt (last resort)
# ──────────────────────────────────────────────────────────────────────────────
setup_git_auth() {
  # 0. Prefer an already-configured git credential helper (e.g. git-credential-manager).
  # In some orgs an AAD CLI token is a *valid* token but still rejected for git with
  # HTTP 403, while the user's helper authenticates fine — so never override a helper.
  if git config --get credential.helper >/dev/null 2>&1; then
    ok "Git: using configured credential helper ($(git config --get credential.helper))"
    return
  fi

  # 1. Try Azure AD token — works when logged in via 'az login' with a corporate account
  local token=""
  token=$(az account get-access-token \
    --resource "499b84ac-1321-427f-aa17-267ca6975798" \
    --query accessToken -o tsv 2>/dev/null) || true

  if [[ -n "$token" ]]; then
    # Inject the Bearer token as an HTTP header for all git operations this session.
    # GIT_CONFIG_COUNT/KEY/VALUE are supported since git 2.32.
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="http.https://dev.azure.com/.extraheader"
    export GIT_CONFIG_VALUE_0="Authorization: Bearer ${token}"
    ok "Git: authenticated via Azure AD (no PAT required)"
    return
  fi

  # 2. PAT via environment variable
  local pat="${AZURE_DEVOPS_EXT_PAT:-}"

  # 3. Interactive PAT prompt
  if [[ -z "$pat" ]]; then
    warn "Azure AD token not available — falling back to PAT"
    echo "    Tip: run 'az login' with your work account to skip this in the future."
    echo ""
    printf "    PAT (input hidden): "
    read -rs pat
    echo ""
    if [[ -z "$pat" ]]; then
      err "No PAT provided — git operations will fail."
      return
    fi
  fi

  # Set up GIT_ASKPASS so git never prompts interactively
  local askpass_file
  askpass_file=$(mktemp)
  chmod 700 "$askpass_file"
  printf '#!/bin/sh\nprintf "%%s" "%s"\n' "$pat" > "$askpass_file"
  export GIT_ASKPASS="$askpass_file"
  trap 'rm -f "$askpass_file"' EXIT
  ok "Git: authenticated via PAT"
}

# ──────────────────────────────────────────────────────────────────────────────
# Interactive project selection
# ──────────────────────────────────────────────────────────────────────────────
select_projects() {
  if [[ -n "$SELECTED_PROJECTS" && "$RESELECT" == "false" ]]; then
    info "Using saved project selection (run with --reselect to change)"
    return
  fi

  section "Project selection"
  info "Fetching project list from Azure DevOps..."

  local all_projects
  all_projects=$(az devops project list --org "$ORG_URL" --top 500 \
    --query "value[].name" -o tsv 2>/dev/null | sort) || {
    err "Failed to fetch projects."
    exit 1
  }

  if [[ -z "$all_projects" ]]; then
    err "No projects returned — check your permissions."
    exit 1
  fi

  # Parse previously saved selection so we can pre-mark it
  local -a prev_selected=()
  if [[ -n "$SELECTED_PROJECTS" ]]; then
    IFS=',' read -ra prev_selected <<< "$SELECTED_PROJECTS"
    for i in "${!prev_selected[@]}"; do
      prev_selected[$i]="${prev_selected[$i]// /}"
    done
  fi

  local selected=""

  if command -v fzf &>/dev/null; then
    local fzf_input="$all_projects"
    local fzf_bind_load=""

    if [[ ${#prev_selected[@]} -gt 0 ]]; then
      # Split list: previously selected items first (sorted), rest after (sorted).
      # This groups them at the top so the load binding can select them by position.
      local sorted_prev="" sorted_rest=""
      while IFS= read -r proj; do
        local is_prev=false
        for p in "${prev_selected[@]}"; do
          [[ "$p" == "$proj" ]] && is_prev=true && break
        done
        if [[ "$is_prev" == "true" ]]; then
          sorted_prev+="${proj}"$'\n'
        else
          sorted_rest+="${proj}"$'\n'
        fi
      done <<< "$all_projects"

      fzf_input=$(printf '%s%s' "$sorted_prev" "$sorted_rest" | grep -v '^$')

      # Count how many prev items actually still exist on the remote
      local n_found=0
      [[ -n "$sorted_prev" ]] && n_found=$(echo "$sorted_prev" | grep -c '^.' || true)

      if [[ $n_found -gt 0 ]]; then
        # fzf starts the cursor at position 0. Each "select+down" marks the current
        # item and moves to the next, pre-selecting exactly the first n_found items.
        local bind_str=""
        for ((i = 0; i < n_found; i++)); do
          [[ $i -gt 0 ]] && bind_str+="+"
          bind_str+="select+down"
        done
        fzf_bind_load="$bind_str"
      fi
    fi

    local -a fzf_args=(
      --multi
      --prompt="Select projects > "
      --header="TAB = toggle  |  ENTER = confirm  |  Ctrl+A = all  |  Ctrl+D = none"
      --height=60%
      --border=rounded
      --info=inline
      --bind='ctrl-d:deselect-all'
    )
    [[ -n "$fzf_bind_load" ]] && fzf_args+=(--bind "load:${fzf_bind_load}")

    selected=$(echo "$fzf_input" | fzf "${fzf_args[@]}") || true

  else
    warn "fzf not installed — falling back to numbered list."
    echo "    Tip: install fzf for a better selection experience"
    echo "    Linux: sudo apt install fzf   macOS: brew install fzf"
    echo ""

    local i=1
    local -a proj_arr=()
    local -a default_nums=()
    while IFS= read -r proj; do
      proj_arr+=("$proj")
      local is_prev=false
      for p in "${prev_selected[@]}"; do
        [[ "$p" == "$proj" ]] && is_prev=true && break
      done
      local marker="   "
      [[ "$is_prev" == "true" ]] && marker=" ✓ " && default_nums+=("$i")
      printf "    %3d)%s%s\n" "$i" "$marker" "$proj"
      ((i++))
    done <<< "$all_projects"

    echo ""
    local default_str=""
    [[ ${#default_nums[@]} -gt 0 ]] && default_str=$(IFS=','; echo "${default_nums[*]}")

    if [[ -n "$default_str" ]]; then
      printf "  Enter numbers (comma-separated) [%s]: " "$default_str"
    else
      printf "  Enter numbers (comma-separated, e.g. 1,3,5): "
    fi
    read -r choices
    [[ -z "$choices" && -n "$default_str" ]] && choices="$default_str"

    local selected_lines=()
    IFS=',' read -ra nums <<< "$choices"
    for num in "${nums[@]}"; do
      num="${num// /}"
      if [[ "$num" =~ ^[0-9]+$ ]]; then
        local idx=$((num - 1))
        [[ $idx -ge 0 && $idx -lt ${#proj_arr[@]} ]] && selected_lines+=("${proj_arr[$idx]}")
      fi
    done
    [[ ${#selected_lines[@]} -gt 0 ]] && selected=$(printf '%s\n' "${selected_lines[@]}")
  fi

  if [[ -z "$selected" ]]; then
    warn "No projects selected — nothing to sync."
    exit 0
  fi

  SELECTED_PROJECTS=$(echo "$selected" | paste -sd ',' -)
  save_config
  ok "Selection saved: ${SELECTED_PROJECTS}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Sync helpers
# ──────────────────────────────────────────────────────────────────────────────

# Prints a fixed-width operation label so the trailing status ("done"/"failed")
# always starts at the same column, regardless of repo name length.
# Names longer than 55 chars are truncated with "…" to keep output readable.
print_op() {
  local op="$1" name="$2"
  local max_name=55
  if [[ ${#name} -gt $max_name ]]; then
    name="${name:0:$((max_name - 1))}…"
  fi
  printf "    %-12s%-57s" "${op}" "${name}..."
}

# Returns true if the repo has staged or unstaged changes to tracked files.
# Untracked files (^??) are intentionally excluded — they don't block a pull.
has_uncommitted_changes() {
  local dir="$1"
  local changes
  changes=$(git -C "$dir" status --short 2>/dev/null | grep -v '^??' || true)
  [[ -n "$changes" ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# Sync a single project
# ──────────────────────────────────────────────────────────────────────────────
sync_project() {
  local project="$1"
  local project_dir="${BASEPATH}/${project}"

  echo -e "\n  ${BOLD}${CYAN}▶  ${project}${NC}"
  mkdir -p "$project_dir"

  # Fetch repo list as JSON
  local repo_json
  repo_json=$(az repos list --project "$project" --org "$ORG_URL" \
    -o json 2>/dev/null) || {
    warn "${project}: could not fetch repo list — skipping"
    FAILED+=("${project}/*")
    return
  }

  # Validate and count
  local repo_count=0
  repo_count=$(echo "$repo_json" | jq 'length' 2>/dev/null) || repo_count=0

  if [[ "$repo_count" -eq 0 ]]; then
    warn "${project}: no repositories found (empty project or insufficient access)"
    return
  fi

  # Extract name + remoteUrl as TSV in a single jq pass
  local repo_tsv
  repo_tsv=$(echo "$repo_json" | jq -r '.[] | [.name, .remoteUrl] | @tsv' 2>/dev/null) || {
    warn "${project}: failed to parse repo JSON"
    FAILED+=("${project}/*")
    return
  }

  # Track remote repo names for orphan detection below
  local remote_names=()

  while IFS=$'\t' read -r name url; do
    remote_names+=("$name")
    local repo_dir="${project_dir}/${name}"
    [[ "$USE_SSH" == "true" ]] && url="$(to_ssh_url "$url")"

    if [[ ! -d "${repo_dir}/.git" ]]; then
      # ── Clone missing repo ─────────────────────────────────────────────────
      print_op "Cloning" "$name"
      if git clone --quiet "$url" "$repo_dir" 2>/dev/null; then
        echo -e "${GREEN}done${NC}"
        CLONED+=("${project}/${name}")
      else
        echo -e "${RED}failed${NC}"
        FAILED+=("${project}/${name}")
      fi

    else
      # ── Existing repo: realign origin to the desired transport, then sync ───
      # Repos cloned before SSH support still carry an HTTPS origin, which sends
      # git through git-credential-manager → OAuth device code (blocked here).
      # Rewrite origin to the SSH URL so pull/fetch never invokes GCM.
      local current_url
      current_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "")
      if [[ -n "$current_url" && "$current_url" != "$url" ]]; then
        git -C "$repo_dir" remote set-url origin "$url" 2>/dev/null || true
      fi

      local branch
      branch=$(git -C "$repo_dir" symbolic-ref --short -q HEAD 2>/dev/null) \
        || branch="detached@$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo '?')"

      if [[ "$branch" == "main" || "$branch" == "master" ]]; then
        if has_uncommitted_changes "$repo_dir"; then
          warn "${name} (${branch}): uncommitted changes — skipping pull"
          SKIPPED+=("${project}/${name}")
        else
          print_op "Pulling" "${name} (${branch})"
          if git -C "$repo_dir" pull --quiet 2>/dev/null; then
            echo -e "${GREEN}done${NC}"
            PULLED+=("${project}/${name}")
          else
            echo -e "${RED}failed${NC}"
            FAILED+=("${project}/${name}")
          fi
        fi
      else
        print_op "Fetching" "${name} (${branch})"
        if git -C "$repo_dir" fetch --quiet 2>/dev/null; then
          echo -e "${GREEN}done${NC}"
          FETCHED+=("${project}/${name}")
        else
          echo -e "${RED}failed${NC}"
          FAILED+=("${project}/${name}")
        fi
      fi
    fi

  done <<< "$repo_tsv"

  # ── Orphan detection: local dirs no longer present on remote ───────────────
  while IFS= read -r local_dir; do
    [[ ! -d "${local_dir}/.git" ]] && continue

    local local_name
    local_name=$(basename "$local_dir")

    local found=false
    if [[ ${#remote_names[@]} -gt 0 ]]; then
      for rname in "${remote_names[@]}"; do
        [[ "$rname" == "$local_name" ]] && found=true && break
      done
    fi

    if [[ "$found" == "false" ]]; then
      echo ""
      warn "${local_name}: repository no longer exists on remote"
      if ! { : >/dev/tty; } 2>/dev/null; then
        info "Non-interactive shell — keeping ${local_name} (delete manually if intended)"
        continue
      fi
      printf "    Delete local copy '%s'? [y/N] " "$local_dir"
      read -r confirm1 </dev/tty
      if [[ "$confirm1" =~ ^[Yy]$ ]]; then
        printf "    Are you sure? This cannot be undone. [y/N] "
        read -r confirm2 </dev/tty
        if [[ "$confirm2" =~ ^[Yy]$ ]]; then
          rm -rf "$local_dir"
          ok "Deleted ${local_name}"
          DELETED+=("${project}/${local_name}")
        else
          info "Kept ${local_name}"
        fi
      else
        info "Kept ${local_name}"
      fi
    fi
  done < <(find "$project_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
}

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${BOLD}  ══════════════════════════════════════${NC}"
  echo -e "${BOLD}    Sync summary${NC}"
  echo -e "${BOLD}  ══════════════════════════════════════${NC}"
  printf "    ${GREEN}%-10s${NC} %d\n" "Cloned"  "${#CLONED[@]}"
  printf "    ${GREEN}%-10s${NC} %d\n" "Pulled"  "${#PULLED[@]}"
  printf "    ${GREEN}%-10s${NC} %d\n" "Fetched" "${#FETCHED[@]}"
  printf "    ${RED}%-10s${NC}   %d\n" "Deleted" "${#DELETED[@]}"
  printf "    ${YELLOW}%-10s${NC} %d\n" "Skipped" "${#SKIPPED[@]}"
  printf "    ${RED}%-10s${NC}   %d\n" "Failed"  "${#FAILED[@]}"

  if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo -e "\n    ${YELLOW}Skipped (uncommitted changes):${NC}"
    for r in "${SKIPPED[@]}"; do printf "      · %s\n" "$r"; done
    echo "    Run 'git status' in each repo above to review changes."
  fi

  if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo -e "\n    ${RED}Failed:${NC}"
    for r in "${FAILED[@]}"; do printf "      · %s\n" "$r"; done
  fi
  echo ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Repo index (entrypoint discovery)
# Writes BASEPATH/REPOS.md — a Project→Repo map (branch, dirty state, last commit)
# scanned from the filesystem, so it reflects every repo actually cloned, not only
# the synced selection. Regenerated on every run. Also seeds BASEPATH/CLAUDE.md as
# the auto-loaded entrypoint if it does not exist yet.
# ──────────────────────────────────────────────────────────────────────────────
generate_index() {
  section "Updating repo index"

  local index_file="${BASEPATH}/${INDEX_FILE}"
  local tmp
  tmp=$(mktemp)

  # All repo git dirs at the fixed BASEPATH/Project/Repo/.git depth.
  # LC_ALL=C forces byte-wise sort so each Project/ prefix stays contiguous
  # (locale collation interleaves similar prefixes and breaks grouping).
  local -a gitdirs=()
  while IFS= read -r g; do
    gitdirs+=("$g")
  done < <(find "$BASEPATH" -mindepth 3 -maxdepth 3 -name .git -type d 2>/dev/null | LC_ALL=C sort)

  local repo_total=${#gitdirs[@]}
  local proj_total=0
  if [[ $repo_total -gt 0 ]]; then
    proj_total=$(for g in "${gitdirs[@]}"; do
      basename "$(dirname "$(dirname "$g")")"
    done | sort -u | wc -l)
  fi

  {
    echo "# Local Repo Index"
    echo ""
    echo "<!-- AUTO-GENERATED by ado-sync.sh — do not edit by hand. Re-run ./ado-sync.sh to refresh. -->"
    echo ""
    echo "_Generated $(date '+%Y-%m-%d %H:%M') · BASEPATH \`${BASEPATH}\` · ${repo_total} repos / ${proj_total} projects · \`●\` = uncommitted changes_"

    local current_project="" g repo_dir repo_name project branch dirty last
    for g in "${gitdirs[@]}"; do
      repo_dir=$(dirname "$g")
      repo_name=$(basename "$repo_dir")
      project=$(basename "$(dirname "$repo_dir")")

      if [[ "$project" != "$current_project" ]]; then
        current_project="$project"
        echo ""
        echo "## ${project}"
      fi

      # symbolic-ref resolves the branch name even on an unborn branch (empty repo,
      # where rev-parse --abbrev-ref fails); fall back to a short SHA when detached.
      branch=$(git -C "$repo_dir" symbolic-ref --short -q HEAD 2>/dev/null) \
        || branch="detached@$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo '?')"
      dirty=""
      has_uncommitted_changes "$repo_dir" && dirty=" \`●\`"

      # Relative date + subject of the last commit, truncated to keep lines short.
      last=$(git -C "$repo_dir" log -1 --format='%cr: %s' 2>/dev/null || true)
      if [[ -n "$last" ]]; then
        [[ ${#last} -gt 60 ]] && last="${last:0:59}…"
        last=" · ${last}"
      fi

      echo "- \`${repo_name}\` — ${branch}${dirty}${last}"
    done
  } > "$tmp"

  mv "$tmp" "$index_file"
  ok "Repo index → ${index_file} (${repo_total} repos / ${proj_total} projects)"

  ensure_claude_entrypoint
}

# Creates BASEPATH/CLAUDE.md as the auto-loaded entrypoint only when it is missing.
# An existing file is user-owned and never overwritten.
ensure_claude_entrypoint() {
  local entry="${BASEPATH}/${ENTRYPOINT_FILE}"
  [[ -f "$entry" ]] && return 0

  cat > "$entry" <<EOF
# dev/ — Azure DevOps workspace

Local mirror of Azure DevOps repos. Layout: \`{ADO-Project}/{Repo}/\`
(org: ${ORG_URL}). Kept in sync with \`./ado-sync.sh\` (selection in \`${CONFIG_FILE}\`).

The live repo map (auto-generated — do not hand-edit) is imported below:

@${INDEX_FILE}

Fallback if the map is missing: \`find . -mindepth 3 -maxdepth 3 -name .git -type d\`
EOF
  ok "Created entrypoint → ${entry}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Usage
# ──────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

  Usage: $(basename "$0") [OPTIONS]

  Sync Azure DevOps repos for a configured organisation.
  Local structure: BASEPATH/Project/Repo/

  Options:
    -r, --reselect    Re-open interactive project selection
    --https           Use HTTPS URLs instead of SSH (default: SSH)
    -h, --help        Show this help

  Config file: ${CONFIG_FILE}
    Holds ORG_URL, BASEPATH and SELECTED_PROJECTS. Created on first run;
    edit it any time. It is intentionally NOT version-controlled.

  Examples:
    ./$(basename "$0")              # sync using saved org + project selection
    ./$(basename "$0") --reselect  # choose projects again before syncing

EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────────────────────
main() {
  for arg in "$@"; do
    case "$arg" in
      -r|--reselect) RESELECT=true ;;
      --https)       USE_SSH=false ;;
      -h|--help)     usage; exit 0 ;;
      *) err "Unknown option: ${arg}"; usage; exit 1 ;;
    esac
  done

  # Config must load first: it provides ORG_URL, which check_prerequisites needs.
  load_config
  print_banner
  check_prerequisites
  setup_git_auth
  select_projects

  section "Syncing repositories"
  info "Basepath : ${BASEPATH}"

  # Sort projects alphabetically and display one per line
  IFS=',' read -ra projects <<< "$SELECTED_PROJECTS"
  local sorted_projects=()
  while IFS= read -r p; do
    p="${p// /}"
    [[ -n "$p" ]] && sorted_projects+=("$p")
  done < <(printf '%s\n' "${projects[@]}" | sort)

  echo -e "  ${CYAN}${BOLD}[INFO]${NC}  Projects :"
  for p in "${sorted_projects[@]}"; do
    echo "             · ${p}"
  done

  for project in "${sorted_projects[@]}"; do
    sync_project "$project"
  done

  generate_index || warn "Index update failed — repo list may be stale"

  print_summary
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  main "$@"
fi
