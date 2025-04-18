[ -f "$HOME/.slimzsh/slim.zsh" ] && source "$HOME/.slimzsh/slim.zsh"

addToPathFront() {
    if [[ ! -z "$2" ]] || [[ "$PATH" != *"$1"* ]]; then
        export PATH=$1:$PATH
    fi
}

# Atuin
if (( $+commands[atuin] )); then
  eval "$(atuin init zsh)"
fi

export EDITOR=nvim

export GOPATH=$HOME/.local/go
addToPathFront /usr/local/go/bin

export N_PREFIX="$HOME/.local/n"
addToPathFront $HOME/.local/n/bin/

addToPathFront $HOME/.local/.npm-global/bin
addToPathFront $HOME/.local/scripts
addToPathFront $HOME/.local/bin
addToPathFront $HOME/.local/npm/bin

# Aliases
alias git2ssh='git remote set-url origin "$(git remote get-url origin | sed -E '\''s,^https://([^/]*)/(.*)$,git@\1:\2,'\'')"'
alias git2https='git remote set-url origin "$(git remote get-url origin | sed -E '\''s,^git@([^:]*):/*(.*)$,https://\1/\2,'\'')"'
alias vi=nvim
