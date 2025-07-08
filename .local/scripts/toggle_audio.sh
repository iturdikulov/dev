#!/bin/sh
# pactl get-default-sink to determine sinks

sink1=alsa_output.pci-0000_2d_00.1.hdmi-stereo-extra1
sink2=alsa_output.pci-0000_2f_00.4.analog-stereo

sink_current=`pactl get-default-sink`
case $sink_current in
  $sink1) pactl set-default-sink $sink2 ;;
  $sink2) pactl set-default-sink $sink1 ;;
  *) pactl set-default-sink $sink1 ;;
esac
