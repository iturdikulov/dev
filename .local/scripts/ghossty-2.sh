#!/bin/sh
sleep 5 
ghostty --class=com.inom.ghostty-2 &
sleep 2
kdotool search --class "com.inom.ghostty-2" windowmove 1920 0 windowstate --add MAXIMIZED --add SKIP_TASKBAR
