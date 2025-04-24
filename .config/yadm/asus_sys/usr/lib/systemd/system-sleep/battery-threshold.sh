#!/bin/sh
case $1/$2 in
  pre/*)
    echo "Going to $2..."
    ;;
  post/*)
    echo "Waking up from $2..."
    echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold
    ;;
esac
