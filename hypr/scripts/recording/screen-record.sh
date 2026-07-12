#!/usr/bin/env bash

RECORD_DIR="$HOME/Videos/Recordings"
mkdir -p "$RECORD_DIR"

FILENAME="$RECORD_DIR/recording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"

# Select recording area
GEOMETRY=$(slurp)

# Cancelled selection
if [ -z "$GEOMETRY" ]; then
    notify-send "Screen Recording" "Recording cancelled"
    exit 1
fi

notify-send "Screen Recording" "Recording started with audio"

# Record selected region at 60 FPS with system audio
wl-screenrec \
    -g "$GEOMETRY" \
    -m 60 \
    --audio \
    -f "$FILENAME"

notify-send "Screen Recording" "Recording saved to $FILENAME"
