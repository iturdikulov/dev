[ -f "$HOME/.config/slimzsh/slim.zsh" ] && source "$HOME/.config/slimzsh/slim.zsh"

precmd() {
    print -Pn "\e]133;A\e\\"
}
unsetopt correct_all

if [ -f "$HOME/.config/io.datasette.llm/keys.json" ]; then
    export OPENROUTER_API_KEY="$(jq -r .openrouter $HOME/.config/io.datasette.llm/keys.json)"
fi

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

export NNN_PLUG="d:dragdrop;D:dups;c:chksum;f:fzcd;F:fixname;m:mymount;o:oldbigfile;R:rsync;s:suedit";
export NNN_TRASH="2"

export EDITOR=nvim
export PASSWORD_STORE_ENABLE_EXTENSIONS=true

export GOPATH=$HOME/.local/go
addToPathFront /usr/local/go/bin

export N_PREFIX="$HOME/.local/n"
addToPathFront $HOME/.local/n/bin

addToPathFront $HOME/.local/tmux/bin
addToPathFront $HOME/.local/scripts
addToPathFront $HOME/.config/nnn/plugins
addToPathFront $HOME/.local/.npm-global/bin
addToPathFront $HOME/.local/bin
addToPathFront $HOME/.local/go/bin
addToPathFront $HOME/.local/npm/bin

addToPath /usr/local/games
addToPath /usr/games

alias sudo='sudo '
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
mkdirp() {
  mkdir -p "$1" && cd "$1";
}; compdef take=mkdir

alias wget='wget2'
alias py='python3'

alias y='wl-copy'
alias p='wl-paste'

alias reboot='reboot || sudo reboot'

alias free='free -m' # show sizes in MB
alias ports='netstat -tpl'

alias path_dirs='echo -e ${PATH//:/\\n}'
alias df='df -h'                          # human-readable sizes
alias info='info --vi-keys' # Info vi mode
alias watch='watch --color' # Color using watch
alias chown="chown --preserve-root" # Do not do chown for root directory
alias chmod="chmod --preserve-root"
alias E="SUDO_EDITOR=nvim sudo -e"

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

alias jc='journalctl -xeu'
alias sc=systemctl

if (( $+commands[apt] )); then
    alias apts='apt-cache search'
    alias aptshow='apt-cache show'
    alias aptinst='sudo apt-get install -V'
    alias aptupd='sudo apt-get update'
    alias aptupg='sudo apt-get dist-upgrade -V && sudo apt-get autoremove'
    alias aptupgd='sudo apt-get update && sudo apt-get dist-upgrade -V && sudo apt-get autoremove'
    alias aptrm='sudo apt-get remove'
    alias aptpurge='sudo apt-get remove --purge'
    alias chkup='/usr/lib/update-notifier/apt-check -p --human-readable'
    alias chkboot='cat /var/run/reboot-required'
    alias pkgfiles='dpkg --listfiles'
fi

weather () {
    curl -s wttr.in/$1?3nQ | head -n -1 | grep -v ┼
}

qcode (){
    cat $@ | qrencode -t ansiutf8
}

q() {
    llm -s "Use a brief style for answer, limit output to 140-500 characters." "$*"|glow
}

def() {
    llm -s "Define the word "[WORD]" in simple English, providing a few common example sentence and a brief Russian translation of the definition. Also, include common synonyms and antonyms, output should fit in $(tput lines) lines and $(tput cols)." "$*"|glow
}
