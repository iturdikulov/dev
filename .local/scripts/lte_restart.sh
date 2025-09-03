#!/bin/sh
echo "Restart LTE1 on Mikrotik"
ssh mikrotik "/interface disable lte1;:delay 5000ms;/interface enable lte1"
