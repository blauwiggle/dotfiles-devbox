# ============================================================
#  Homebrew (Linux or macOS)
# ============================================================
if [[ -d /home/linuxbrew/.linuxbrew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -d /opt/homebrew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ============================================================
#  PATH (deduped + idempotent across re-sourcing)
# ============================================================
typeset -U path PATH
path=(
  $HOME/.local/bin
  $HOME/go/bin
  ${KREW_ROOT:-$HOME/.krew}/bin
  $HOME/development/flutter/bin
  $HOME/.gem/bin
  $HOME/.jbang/bin
  $HOME/.dotnet
  $HOME/.dotnet/tools
  $HOME/.azure/bin
  $path
)
export DOTNET_ROOT="$HOME/.dotnet"

# Android SDK (macOS Homebrew location; guarded so WSL ignores it)
if [[ -d /opt/homebrew/share/android-commandlinetools ]]; then
  export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
  path+=($ANDROID_HOME/cmdline-tools/latest/bin $ANDROID_HOME/platform-tools)
fi

# ============================================================
#  Locale
# ============================================================
export LANG=en_US.UTF-8

# ============================================================
#  History
# ============================================================
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY SHARE_HISTORY INC_APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS HIST_FIND_NO_DUPS

# ============================================================
#  Completion (cached compinit + cached kubectl completion)
# ============================================================
fpath=(~/.zsh/completions $fpath)

# Refresh kubectl completion at most once/day (no kubectl spawn every start)
if command -v kubectl >/dev/null; then
  if [[ ! -e ~/.zsh/completions/_kubectl || -n ~/.zsh/completions/_kubectl(#qN.mh+24) ]]; then
    mkdir -p ~/.zsh/completions
    kubectl completion zsh >| ~/.zsh/completions/_kubectl
  fi
fi

autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then compinit; else compinit -C; fi

# terraform completion (guarded - only if terraform is installed)
if command -v terraform >/dev/null; then
  autoload -U +X bashcompinit && bashcompinit
  complete -o nospace -C "$(command -v terraform)" terraform
fi

zstyle ':completion:*' menu yes select

# ============================================================
#  Prompt + shell integrations
# ============================================================
eval "$(starship init zsh)"
eval "$(direnv hook zsh)"

# thefuck init is slow -> load lazily on first use
if command -v thefuck >/dev/null; then
  fuck() { eval "$(thefuck --alias)"; unfunction fuck; fuck "$@"; }
fi

# (disabled toggles kept for reference)
# eval "$(devbox global shellenv --init-hook)"
# source <(docker completion zsh)

# ============================================================
#  Zinit + plugins (turbo / deferred)
# ============================================================
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
  print -P "%F{33} %F{220}Installing %F{33}zinit%F{220}...%f"
  command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
  command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" \
    && print -P "%F{34}Installed.%f" || print -P "%F{160}Clone failed.%f"
fi
source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

zinit light-mode for \
  zdharma-continuum/zinit-annex-as-monitor \
  zdharma-continuum/zinit-annex-bin-gem-node \
  zdharma-continuum/zinit-annex-patch-dl \
  zdharma-continuum/zinit-annex-rust

# plugins - deferred until after first prompt
zinit wait lucid for \
  atload"_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions \
  atload"bindkey '^[[A' history-substring-search-up; bindkey '^[[B' history-substring-search-down" \
    zsh-users/zsh-history-substring-search \
  zsh-users/zsh-syntax-highlighting

# ============================================================
#  Aliases
# ============================================================
alias ls='eza --long --all --no-permissions --no-filesize --no-user --no-time --git'
alias ll='eza --long --all --no-permissions --no-filesize --no-user --git --sort modified'
alias fzfp='fzf --preview "bat --style numbers --color always {}"'
alias cat='bat --paging never --theme DarkNeon --style plain'
alias k=kubectl
alias tf=terraform
alias bru="brew update && brew upgrade && brew cleanup && brew doctor"
alias x="exit"
alias ac="clear"
alias zz="source ~/.zshrc"
alias pip='pip3'
alias wsl='powershell.exe -Command "wsl --shutdown"'
alias j!=jbang

# ============================================================
#  zoxide - MUST stay last (registers chpwd hook after plugins)
# ============================================================
# __zoxide_hook is verified present in chpwd_functions at runtime; the doctor
# check is a false positive under zinit turbo's deferred precmd scheduling.
export _ZO_DOCTOR=0
eval "$(zoxide init --cmd cd zsh)"
