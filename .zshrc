[ -f "$HOME/.slimzsh/slim.zsh" ] && source "$HOME/.slimzsh/slim.zsh"


addToPath() {
    if [[ "$PATH" != *"$1"* ]]; then
        export PATH=$PATH:$1
    fi
}

addToPathFront() {
    if [[ ! -z "$2" ]] || [[ "$PATH" != *"$1"* ]]; then
        export PATH=$1:$PATH
    fi
}


# Init tools
if (( $+commands[zoxide] )); then 
    eval "$(zoxide init zsh)"
fi
if (( $+commands[fzf] )); then 
    source <(fzf --zsh)
fi
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

addToPath /usr/local/games
addToPath /usr/games

# Aliases
alias git2ssh='git remote set-url origin "$(git remote get-url origin | sed -E '\''s,^https://([^/]*)/(.*)$,git@\1:\2,'\'')"'
alias git2https='git remote set-url origin "$(git remote get-url origin | sed -E '\''s,^git@([^:]*):/*(.*)$,https://\1/\2,'\'')"'
alias vi='nvim'
alias mux='tmux attach || tmux new'
alias fd='fdfind'
alias trash='gio trash'
alias f='$(fzf) && nvim -- "$f"'
alias grep='grep --color'
alias l='ls'
alias ls='ls --color=auto'
alias ll='ls -la'          # long listing format
alias l.='ls -d .* --color=auto' # hidden files

