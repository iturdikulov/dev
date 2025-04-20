# Vi mode
bindkey -v
export KEYTIMEOUT=1

# Other conveniences
bindkey -M viins '^a' beginning-of-line
bindkey -M viins '^x^x' push-line-or-edit

# Exit with C-D
exit_zsh() { exit }
zle -N exit_zsh
bindkey -M emacs '^D' exit_zsh
bindkey -M vicmd '^D' exit_zsh
bindkey -M viins '^D' exit_zsh

# Up arrow:
bindkey '\e[A' history-substring-search-up
bindkey '\eOA' history-substring-search-up
# Down arrow:
bindkey '\e[B' history-substring-search-down
bindkey '\eOB' history-substring-search-down

# C-p/C-n previous and next command
bindkey "^P" up-line-or-search
bindkey "^N" down-line-or-search

# C-z to toggle current process (background/foreground)
fancy-ctrl-z () {
  if [[ $#BUFFER -eq 0 ]]; then
    BUFFER="fg"
    zle accept-line
  else
    zle push-input
    zle clear-screen
  fi
}
zle -N fancy-ctrl-z
bindkey '^Z' fancy-ctrl-z

# Completing words in buffer in tmux
if [ -n "$TMUX" ]; then
  _tmux_pane_words() {
    local expl
    local -a w
    if [[ -z "$TMUX_PANE" ]]; then
      _message "not running inside tmux!"
      return 1
    fi
    w=( ${(u)=$(tmux capture-pane \; show-buffer \; delete-buffer)} )
    _wanted values expl 'words from current tmux pane' compadd -a w
  }

  zle -C tmux-pane-words-prefix   complete-word _generic
  zle -C tmux-pane-words-anywhere complete-word _generic

  bindkey -M viins '^x^n' tmux-pane-words-prefix
  bindkey -M viins '^x^o' tmux-pane-words-anywhere
  zstyle ':completion:tmux-pane-words-(prefix|anywhere):*' completer _tmux_pane_words
  zstyle ':completion:tmux-pane-words-(prefix|anywhere):*' ignore-line current
  zstyle ':completion:tmux-pane-words-anywhere:*' matcher-list 'b:=* m:{A-Za-z}={a-zA-Z}'

fi

# Vim's C-x C-l in zsh
history-beginning-search-backward-then-append() {
  zle history-beginning-search-backward
  zle vi-add-eol
}
zle -N history-beginning-search-backward-then-append
bindkey -M viins '^x^l' history-beginning-search-backward-then-append

# fzf
if (( $+commands[fd] )); then
  export FZF_DEFAULT_OPTS="--reverse --ansi"
  export FZF_DEFAULT_COMMAND="fd ."
fi
if [ -n "${commands[fzf-share]}" ]; then
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="fd -t d . $HOME"
  export FZF_CTRL_R_COMMAND=
  source "$(fzf-share)/key-bindings.zsh"
fi

# atuin
if (( $+commands[atuin] )); then
  eval "$(atuin init zsh)"
fi