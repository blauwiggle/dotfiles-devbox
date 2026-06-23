# dotfiles-devbox

Reproducible setup for an **Azure DevOps work box on WSL2** (also runs on plain
Linux/macOS for the shell parts). One `./install.sh` turns a fresh machine into a
working environment: Homebrew toolchain, tuned zsh, WSL/Windows-Terminal config,
git identity + Azure DevOps credential manager, and a restored Claude Code setup.

Organisation-agnostic by design — no employer-specific values are committed; the
sync tool prompts for your Azure DevOps org URL on first run.

## Quick start (new machine)

```bash
git clone https://github.com/blauwiggle/dotfiles-devbox.git ~/dotfiles-devbox
cd ~/dotfiles-devbox
./install.sh --check      # read-only: what's missing?
./install.sh              # full bootstrap (idempotent)
```

> `install.sh` runs under **bash** — no zsh/`.zshrc` needed to bootstrap. It installs Homebrew + every tool (incl. zsh) and writes `~/.zshrc`.
> **Order:** `./install.sh` first, then `chsh -s "$(command -v zsh)"` to make zsh your login shell, then log out/in.
> Finally run `claude` to authenticate and migrate old conversations (below).

## What's in here

| Path | Purpose |
|---|---|
| `install.sh` | Idempotent bootstrap. `--check` = read-only prereq report. Flags: `SKIP_GIT=1`, `SKIP_CLAUDE=1`, `SSH_KEYGEN=1`. |
| `prereq-check.sh` | Lists missing tools, changes nothing. |
| `Brewfile.linux` | linuxbrew CLI tools + casks (`brew bundle`). |
| `.zshrc` | Performance-tuned zsh (zinit turbo, cached completions, ~0.7s startup). |
| `git/bootstrap-git.sh` | Sets git identity (env/prompt), a single clean git-credential-manager helper, `useHttpPath` for `dev.azure.com`. `--ssh` generates an ed25519 key. |
| `git/gitconfig.example` | Reference template for the above. |
| `claude/` | Claude Code config backup + `restore.sh` (copies into `~/.claude`, reinstalls plugins from `plugins.manifest`). Secrets are **not** included. |
| `ado-sync.sh` | Azure DevOps repo sync. Prompts for org URL on first run → `~/.ado-sync.conf`. Clones/pulls/fetches and writes a local `REPOS.md`. |
| `wsl/` | `.wslconfig` (copied to `C:`), inotify sysctl, recovery script. |
| `windows-terminal/` | Versioned `settings.json` + `deploy.sh` (`backup`/`restore`). Username is tokenised (`<WIN_USER>`), expanded on restore. |
| `migrate/backup-conversations.sh` | Tars `~/.claude` conversations **out-of-band** (never committed). |

## git / credentials

`git/bootstrap-git.sh` configures git-credential-manager as the single helper and
`credentialStore = cache` (in-memory; switch to `plaintext` for persistence). For
Azure DevOps over HTTPS this is the reliable path — an Azure AD CLI token is often
rejected by the git transport with HTTP 403, so GCM is preferred. SSH is optional
(`./install.sh` with `SSH_KEYGEN=1`, or `./git/bootstrap-git.sh --ssh`).

## Claude Code migration

Config (committed, secret-free) is restored by `claude/restore.sh`. **Conversations
are not committed** — move them out-of-band:

```bash
# OLD box:
./migrate/backup-conversations.sh           # writes ~/claude-conversations-<date>.tar.gz
# copy the tarball to the NEW box, then there (same username + path!):
tar xzf claude-conversations-<date>.tar.gz -C ~/.claude
claude                                       # log in to re-create credentials
```

> Conversation continuity depends on identical `~/.claude/projects/<encoded-cwd>`
> paths, so keep the **same username and workspace path** on the new box.

## WSL config (`wsl/`)

`.wslconfig` lives on the Windows C: drive (copied, not symlinked); `99-claude-heavy.conf`
raises inotify limits for VS Code + Claude. `./wsl/deploy.sh`, then `wsl --shutdown`.

## Notes

- Do **not** run the macOS `~/dotfiles/install.sh` here — its Stow step clashes with the `~/.zshrc` symlink managed here.
- `~/.ado-sync.conf`, `REPOS.md`, SSH keys and Claude credentials are git-ignored and never published.
