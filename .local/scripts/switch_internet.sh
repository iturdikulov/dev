#!/bin/sh

if [ "$#" -ne 1 ]; then
    echo "Usage: $0"
    exit 1
fi

if [ "$1" = "wan" ]; then
    ssh root@router 'ifdown wwan && ifdown wwan2 && ifup wan'
elif [ "$1" = "wwan" ]; then
    ssh root@router 'ifdown wan && ifdown wwan2 && ifup wwan'
else
    ssh root@router 'ifdown wan && ifdown wwan && ifup wwan2'
fi
