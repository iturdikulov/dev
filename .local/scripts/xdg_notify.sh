#!/bin/sh
XDG_RUNTIME_DIR=/run/user/$(id -u)
export  XDG_RUNTIME_DIR
notify-send "$*"
