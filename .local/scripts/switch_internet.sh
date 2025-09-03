#!/bin/sh

if [ "$#" -ne 1 ]; then
    echo "Usage: $0"
    exit 1
fi

if [ "$1" = "wan" ]; then
    ssh root@router 'ifdown wwan && ifup wan'
else
    ssh root@router 'ifdown wan && ifup wwan'
fi
