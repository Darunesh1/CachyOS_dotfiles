#!/usr/bin/env bash

STATE_FILE="/tmp/hypridle-paused"

if [[ -f "$STATE_FILE" ]]; then
    # Resume idle handling
    pkill -USR2 hypridle
    rm -f "$STATE_FILE"
else
    # Pause idle handling
    pkill -USR1 hypridle
    touch "$STATE_FILE"
fi

# Refresh Waybar immediately
pkill -SIGRTMIN+8 waybar
