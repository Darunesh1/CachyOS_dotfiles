#!/usr/bin/env bash

# Toggle region screen recording. First press selects a region and starts,
# second press stops and saves.
#
# Usage: screen-record.sh [standard|hq]
#
# Both profiles share one PID file, so only one recording runs at a time and
# either keybind stops whichever is active.
#
# Uses wf-recorder. The previous recorder, wl-screenrec, broke when ffmpeg 9
# landed (2026-08-14): the chaotic-aur build is still linked against
# libavutil.so.60 and four other av libs that no longer exist, so it died
# the instant it was launched:
#
#   wl-screenrec: error while loading shared libraries: libavutil.so.60
#
# wf-recorder is in extra and is rebuilt along with ffmpeg, so it tracks the
# system.

PROFILE="${1:-standard}"

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

# ── Quality profiles ───────────────────────────────────────────────────────
# Flag notes (wf-recorder differs from wl-screenrec here):
#   -r  constant framerate            (was -m)
#   -p  video codec params            (-b means B-FRAMES in wf-recorder, NOT bitrate)
#   -c  video codec
#   -C  audio codec
#   -x  pixel format
#   -a  record the default PulseAudio source (the microphone)
#   -y  never prompt to overwrite; there is no terminal to answer it
#
# There is deliberately no audio bitrate flag: wf-recorder ignores -P b=...
# (verified with ffprobe — output stays at AAC's 128k either way).
case "$PROFILE" in
    standard)
        # Everyday capture: 5 Mb/s H.264 in mp4, plays anywhere.
        EXT="mp4"
        ENC_ARGS=(-r 60 -p b=5M -a)
        LABEL="Recording"
        ;;
    hq)
        # High quality: constant-quality H.264 instead of a bitrate cap, so
        # detail is preserved during motion, plus lossless FLAC audio in mkv.
        # mkv also survives a crash or battery cut — an interrupted mp4 does not.
        #
        # crf 14 / preset slow measured at 1.6x realtime for 1080p60 against
        # synthetic noise on this i5-1240P, which is a far harsher load than a
        # desktop. Drop to preset=medium (2.9x) if recording something that
        # itself needs the CPU.
        #
        # For maximum text sharpness use -x yuv444p instead of yuv420p; it
        # measured 2.0x realtime, but 4:4:4 H.264 will not play in browsers,
        # Discord or most phones.
        EXT="mkv"
        ENC_ARGS=(-r 60 -c libx264 -p crf=14 -p preset=slow -x yuv420p -a -C flac)
        LABEL="HQ recording"
        ;;
    *)
        notify-send -u critical "Screen Recording" "Unknown profile: $PROFILE"
        exit 1
        ;;
esac

# ── Select recording region ────────────────────────────────────────────────
# slurp prints "x,y WxH", which is exactly the format wf-recorder -g expects.
GEOMETRY=$(slurp)

if [[ -z "$GEOMETRY" ]]; then
    notify-send "Screen Recording" "Recording cancelled"
    exit 1
fi

# ── Output filename ────────────────────────────────────────────────────────
FILENAME="$RECORD_DIR/recording-$(date +'%Y-%m-%d_%H-%M-%S').$EXT"

# ── Start recording ────────────────────────────────────────────────────────
wf-recorder -g "$GEOMETRY" "${ENC_ARGS[@]}" -y -f "$FILENAME" >"$LOG_FILE" 2>&1 &

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

notify-send "Screen Recording" "$LABEL started"

# Wait until recording stops
wait "$REC_PID"

# Cleanup
rm -f "$PID_FILE"

notify-send "Screen Recording" "Saved to $FILENAME"
