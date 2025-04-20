# Taskwarrior aliases and functions

alias t="noglob task"
alias ti="noglob task in limit:20"
alias tl="noglob task learn limit:20"
alias td='ta dep:"$(task +LATEST uuids)"'

tm() {
    noglob task modify "$@" && t
}
ta() {
    noglob task add "$@" && t
}
fin(){
    task done "$@" && t
}