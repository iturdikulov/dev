#!/bin/sh

cd ~/Desktop/atd/az-containers/ && docker compose down
systemctl reboot
