[ -f "$HOME/.slimzsh/slim.zsh" ] && source "$HOME/.slimzsh/slim.zsh"

# Atuin
if (( $+commands[atuin] )); then
  eval "$(atuin init zsh)"
fi

export EDITOR=nvim
export GOPATH=$HOME/.local/go
export PATH=$PATH:/usr/local/go/bin
