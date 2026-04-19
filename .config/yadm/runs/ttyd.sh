#!/bin/sh

sudo apt-get update
sudo apt-get install -y build-essential cmake git libjson-c-dev libwebsockets-dev
cd /tmp || exit 1
git clone https://github.com/tsl0922/ttyd.git
cd ttyd && mkdir build && cd build || exit 1
cmake ..
make && sudo make install
