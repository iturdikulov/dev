zstyle ':completion:*:*:make:*' tag-order 'targets'

[ -f "$HOME/.config/slimzsh/slim.zsh" ] && source "$HOME/.config/slimzsh/slim.zsh"

precmd() {
    print -Pn "\e]133;A\e\\"
}

set -o vi

# Make Vi mode transitions faster (KEYTIMEOUT is in hundredths of a second)
export KEYTIMEOUT=1

# Beginning search in insert mode, redundant with the up/down arrows above
# but a little easier to press.
bindkey "^P" history-search-backward
bindkey "^N" history-search-forward

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
if (( $+commands[direnv] )); then
    eval "$(direnv hook zsh)"
fi

export NNN_PLUG="d:dragdrop;D:dups;c:chksum;f:fzcd;F:fixname;m:mymount;o:oldbigfile;R:rsync;s:suedit";
export NNN_TRASH="2"

export STARDICT_DATA_DIR="$HOME/Documents/dictionary"
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
addToPathFront $HOME/.local/cling/bin

addToPath /usr/local/games
addToPath /usr/games

alias sudo='sudo '
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

if (( $+commands[wget2] )); then
    alias wget='wget2'
fi

if (( $+commands[nvim] )); then
    alias vi='nvim'
fi

alias ls='ls --color=auto'
if (( $+commands[eza] )); then
  IGNORE_GLOB="UnrealEngine"
  alias eza="eza --group-directories-first --git";
  alias l="eza -bl -I $IGNORE_GLOB";
  alias ll="eza -abghilmu -I $IGNORE_GLOB";
  alias la="LC_COLLATE=C eza -ablF -I $IGNORE_GLOB";
  alias lm='ll --sort=modified'
  alias tree='eza --tree'
  alias treel='eza --color=always --tree|less'
else
  alias l='ls'
  alias ll='ls -la'          # long listing format
  alias la='ls -d .* --color=auto' # hidden files
  alias lm='ls -lt'          # by modification date, newest first
fi

if (( $+commands[fdfind] )); then
  alias fd='fdfind'
  alias fd_non_ascii='fd "[^\u0000-\u007F]+"'  # find non-ascii filenames
fi

alias g='git'
alias py='python3'
alias disk-usage='ncdu --exclude ~/Media --exclude /proc --exclude /sys --exclude /mnt --exclude /media --exclude /dev/shm'

alias y='wl-copy'
alias p='wl-paste'
# fix paste for some X11 apps
alias w2x='wl-paste | xclip -i -selection clipboard'

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
alias mux='tmux attach || tmux new'
alias f='$(fzf) && nvim -- "$f"'
alias grep='grep --color'

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

# Translate aliaes
export ARGOS_DEVICE_TYPE=cuda
toen() {
    argos-translate --from ru --to en "$*"
}

toru() {
    argos-translate --from en --to ru "$*"
}

# Generate HTML output for a command submit session with stdout highlighting.
stdout2html() {
    # Usage example: stdout2html output_name 'leetcode x 1'
    output=$1
    shift
    script --quiet --command "$@"| ansi2html.sh > "$output.html"
}

# An rsync that respects gitignore
rcp() {
    #   -a = -rlptgoD
    #   -r = recursive
    #   -l = copy symlinks as symlinks
    #   -p = preserve permissions
    #   -t = preserve mtimes
    #   -g = preserve owning group
    #   -o = preserve owner
    # -z = use compression
    # -P = show progress on transferred file
    # -J = don't touch mtimes on symlinks (always errors)
    rsync -rtzPJ \
        --include=.git/ \
        "$@"
}

prime-run () {
    __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia "$@"
}

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
    llm -s "Define the word "[WORD]" in simple English, providing a few common example sentence and a brief Russian translation of the definition. Also, include etymology information, common synonyms and antonyms, output should fit in $(tput lines) lines and $(tput cols)." "$*"|glow
}

d() {
    sdcv -nc "$@" | sed 's/<[^>]*>//g' | sed 's/0m.*\w\+\.wav.*/0m/g' | less -R
}

nullify() {
    "$@" > /dev/null 2>&1
}

# Expand ue4cli
ue() {
    ue4cli=$(which ue4)
    engine_path=$($ue4cli root)

  # cd to ue location
    if [[ "$1" == "engine" ]]; then
        cd $engine_path
  # combine clean and build in one command
    elif [[ "$1" == "rebuild" ]]; then
        $ue4cli clean
        $ue4cli build
        if [[ "$2" == "run" ]]; then
            $ue4cli run
        fi
  # build and optionally run while respecting build flags
    elif [[ "$1" == "build" ]]; then
        if [[ "${@: -1}" == "run" ]]; then
            length="$(($# - 2))" # Get length without last param because of 'run'
            $ue4cli build ${@:2:$length}
            $ue4cli run
        else
            shift 1
            $ue4cli build "$@"
        fi
  # Run project files generation, create a symlink for the compile database and fix-up the compile database
    elif [[ "$1" == "gen" ]]; then
        $ue4cli gen
        project=${PWD##*/}
        cat ".vscode/compileCommands_${project}.json" | python -c 'import json,sys
j = json.load(sys.stdin)
for o in j:
  file = o["file"]
  arg = o["arguments"][1]
  o["arguments"] = ["clang++ -std=c++20 -ferror-limit=0 -Wall -Wextra -Wpedantic -Wshadow-all -Wno-unused-parameter " + file + " " + arg]
print(json.dumps(j, indent=2))' > compile_commands.json
  # Pass through all other commands to ue4
    else
        $ue4cli "$@"
    fi
}

if (( $+commands[mpv] )); then
    play() {
        mpv "$@" > /dev/null 2>&1 & disown
    }

    play_lr() {
        RECORDINGS_DIR="$HOME/Videos/record"
        [ -d $RECORDINGS_DIR ] || echo "No $RECORDINGS_DIR directory found"
        RECORDING="$RECORDINGS_DIR/$(ls -Art $RECORDINGS_DIR|tail -n 1)"
        echo "Opening $RECORDING and copying to clipboard"
        echo "$RECORDING"| wl-copy
        mpv --loop-file=yes "$RECORDING"
    }
fi
