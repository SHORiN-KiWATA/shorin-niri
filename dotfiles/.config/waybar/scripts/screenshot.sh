#!/usr/bin/env bash

COORDS=$(slurp)
if [ -z "$COORDS" ]; then
    exit 0
fi
pw-play /usr/share/sounds/freedesktop/stereo/camera-shutter.oga > /dev/null 2>&1 & 
grim -g "$COORDS" - | wl-copy && notify-send "Screenshot" "copy to clipboard"
