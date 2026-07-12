#!/usr/bin/env bash

RECORD_DIR="$HOME/Videos/Recordings"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/wl-screenrec.pid"

mkdir -p "$RECORD_DIR"

# ── Stop recording if already running ──────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")

    if kill -0 "$PID" 2>/dev/null; then
        kill -INT "$PID"
        notify-send "Screen Recording" "Recording stopped and saved"
        exit 0
    fi

    rm -f "$PID_FILE"
fi

# ── Select recording region ────────────────────────────────────────────────
GEOMETRY=$(slurp)

if [[ -z "$GEOMETRY" ]]; then
    notify-send "Screen Recording" "Recording cancelled"
    exit 1
fi

# ── Output filename ────────────────────────────────────────────────────────
FILENAME="$RECORD_DIR/recording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"

# ── Start recording ────────────────────────────────────────────────────────
wl-screenrec \
    -g "$GEOMETRY" \
    -m 60 \
    --audio \
    --audio-bitrate "32 kB" \
    -b "5 MB" \
    -f "$FILENAME" &

REC_PID=$!
echo "$REC_PID" > "$PID_FILE"

notify-send "Screen Recording" "Recording started"

# Wait until recording stops
wait "$REC_PID"

# Cleanup
rm -f "$PID_FILE"

notify-send "Screen Recording" "Saved to $FILENAME"
