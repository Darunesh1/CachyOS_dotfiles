#!/usr/bin/env bash

STATE_FILE="/tmp/hypridle-paused"

if [[ -f "$STATE_FILE" ]]; then
    echo '{"text":"󰅶","tooltip":"Coffee Mode: ON","class":"enabled"}'
else
    echo '{"text":"󰾪","tooltip":"Coffee Mode: OFF","class":"disabled"}'
fi
