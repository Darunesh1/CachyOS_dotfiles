#!/usr/bin/env bash

# Toggle region screen recording. First press selects a region and starts,
# second press stops and saves.
#
# Usage: screen-record.sh [standard|hq] [--area region|full]
#                         [--res native|1440|1080|720] [--audio none|system|mic]
#
#   --area   region: drag a box with slurp (default); full: the focused monitor
#   --res    scale the video down to this height; never scales up (default native)
#   --audio  system: what you hear (default sink's monitor); mic: the default
#            input (default, matching the old behaviour); none: silent
#
# The presets in presets/ are one-line wrappers around these flags, and
# record-menu.sh (SUPER + Print) lists them in rofi.
#
# Every profile shares one PID file, so only one recording runs at a time and
# any recording keybind stops whichever is active.
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

PROFILE="standard"
AREA="region"
RES="native"
AUDIO="mic"

while [[ $# -gt 0 ]]; do
    case "$1" in
        standard|hq) PROFILE="$1" ;;
        --area)      AREA="${2:-}";  shift ;;
        --res)       RES="${2:-}";   shift ;;
        --audio)     AUDIO="${2:-}"; shift ;;
        *)
            notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

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
        notify-send -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Recording stopped and saved"
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
#   -F  ffmpeg filter (used for --res scaling)
#   --audio=DEV  record from a PulseAudio device (set below from --audio)
#   -y  never prompt to overwrite; there is no terminal to answer it
#
# There is deliberately no audio bitrate flag: wf-recorder ignores -P b=...
# (verified with ffprobe — output stays at AAC's 128k either way).
case "$PROFILE" in
    standard)
        # Everyday capture: 5 Mb/s H.264 in mp4, plays anywhere.
        EXT="mp4"
        ENC_ARGS=(-r 60 -p b=5M)
        AUDIO_CODEC=()
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
        ENC_ARGS=(-r 60 -c libx264 -p crf=14 -p preset=slow -x yuv420p)
        AUDIO_CODEC=(-C flac)
        LABEL="HQ recording"
        ;;
    *)
        notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Unknown profile: $PROFILE"
        exit 1
        ;;
esac

# ── Audio ──────────────────────────────────────────────────────────────────
# "system" records the monitor of the default sink -- whatever is playing
# through the speakers or headphones right now, resolved at start time so a
# plugged-in headset is picked up.
case "$AUDIO" in
    none)
        AUDIO_ARGS=() ;;
    mic)
        AUDIO_ARGS=(-a "${AUDIO_CODEC[@]}") ;;
    system)
        SINK=$(pactl get-default-sink 2>/dev/null)
        if [[ -z "$SINK" ]]; then
            notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "No default audio output found"
            exit 1
        fi
        AUDIO_ARGS=(--audio="$SINK.monitor" "${AUDIO_CODEC[@]}") ;;
    *)
        notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Unknown audio mode: $AUDIO"
        exit 1 ;;
esac

# ── Resolution ─────────────────────────────────────────────────────────────
# Scale to the target height, keeping the aspect ratio (-2 = even width, which
# H.264 requires). min(...,ih) means a region smaller than the target is left
# alone rather than upscaled. The comma is escaped for ffmpeg's filter parser.
case "$RES" in
    native)        SCALE_ARGS=() ;;
    1440|1080|720) SCALE_ARGS=(-F "scale=-2:min($RES\\,ih)") ;;
    *)
        notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Unknown resolution: $RES"
        exit 1 ;;
esac

# ── Select what to record ──────────────────────────────────────────────────
case "$AREA" in
    region)
        # slurp prints "x,y WxH", exactly the format wf-recorder -g expects.
        GEOMETRY=$(slurp)
        if [[ -z "$GEOMETRY" ]]; then
            notify-send -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Recording cancelled"
            exit 1
        fi
        TARGET_ARGS=(-g "$GEOMETRY")
        ;;
    full)
        OUTPUT=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name')
        if [[ -z "$OUTPUT" ]]; then
            notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Could not find the focused monitor"
            exit 1
        fi
        TARGET_ARGS=(-o "$OUTPUT")
        ;;
    *)
        notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Unknown area: $AREA"
        exit 1 ;;
esac

# ── Output filename ────────────────────────────────────────────────────────
FILENAME="$RECORD_DIR/recording-$(date +'%Y-%m-%d_%H-%M-%S').$EXT"

# ── Start recording ────────────────────────────────────────────────────────
wf-recorder "${TARGET_ARGS[@]}" "${ENC_ARGS[@]}" "${SCALE_ARGS[@]}" "${AUDIO_ARGS[@]}" \
    -y -f "$FILENAME" >"$LOG_FILE" 2>&1 &

REC_PID=$!
echo "$REC_PID" > "$PID_FILE"

# A recorder that cannot start dies within a moment. Without this check the
# script would still report "Recording started" and leave a PID file behind —
# which is exactly how the broken wl-screenrec went unnoticed for six days.
sleep 1
if ! kill -0 "$REC_PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    notify-send -u critical -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Failed to start — see $LOG_FILE"
    exit 1
fi

notify-send -a "Screen Recording" -i media-record-symbolic "Screen Recording" "$LABEL started ($AREA, $RES, audio: $AUDIO)"

# Wait until recording stops
wait "$REC_PID"

# Cleanup
rm -f "$PID_FILE"

notify-send -a "Screen Recording" -i media-record-symbolic "Screen Recording" "Saved to $FILENAME"
