#!/usr/bin/env bash

# Toggle region screen recording. First press selects a region and starts,
# second press stops and saves.
#
# Uses wf-recorder. The previous recorder, wl-screenrec, broke when ffmpeg 9
# landed (2026-08-14): the chaotic-aur build is still linked against
# libavutil.so.60 while the system now ships .61, so it died on launch.
# wf-recorder is in extra and is rebuilt with ffmpeg, so it tracks the system.

RECORD_DIR="$HOME/Videos/Recordings"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/screen-record.pid"
LOG_FILE="${XDG_RUNTIME_DIR:-/tmp}/screen-record.log"

mkdir -p "$RECORD_DIR"

# ── Stop recording if already running ──────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")

    if kill -0 "$PID" 2>/dev/null; then
        # wf-recorder finalises the file on SIGINT, same as Ctrl+C.
        kill -INT "$PID"
        notify-send "Screen Recording" "Recording stopped and saved"
        exit 0
    fi

    rm -f "$PID_FILE"
fi

# ── Select recording region ────────────────────────────────────────────────
# slurp prints "x,y WxH", which is exactly the format wf-recorder -g expects.
GEOMETRY=$(slurp)

if [[ -z "$GEOMETRY" ]]; then
    notify-send "Screen Recording" "Recording cancelled"
    exit 1
fi

# ── Output filename ────────────────────────────────────────────────────────
FILENAME="$RECORD_DIR/recording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"

# ── Start recording ────────────────────────────────────────────────────────
# Flag notes (wf-recorder differs from wl-screenrec here):
#   -r  constant framerate            (was -m)
#   -p  video codec params, b=5M      (-b means B-FRAMES in wf-recorder, not bitrate)
#   no audio bitrate flag: wf-recorder ignores -P b=..., so AAC's 128k
#       default applies (verified with ffprobe). --audio-bitrate is dropped.
#   -a  record the default PulseAudio source (the microphone), as before
#   -y  never prompt to overwrite; there is no terminal to answer it
wf-recorder \
    -g "$GEOMETRY" \
    -r 60 \
    -a \
    -p b=5M \
    -y \
    -f "$FILENAME" >"$LOG_FILE" 2>&1 &

REC_PID=$!
echo "$REC_PID" > "$PID_FILE"

# A recorder that cannot start dies within a moment. Without this check the
# script would still report "Recording started" and leave a PID file behind —
# which is exactly how the broken wl-screenrec went unnoticed for six days.
sleep 1
if ! kill -0 "$REC_PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    notify-send -u critical "Screen Recording" "Failed to start — see $LOG_FILE"
    exit 1
fi

notify-send "Screen Recording" "Recording started"

# Wait until recording stops
wait "$REC_PID"

# Cleanup
rm -f "$PID_FILE"

notify-send "Screen Recording" "Saved to $FILENAME"
