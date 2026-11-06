#!/usr/bin/env bash
#
# Raise the backlight back to a usable floor. Nothing else.
#
# Why this exists: swayosd/config.toml sets `min_brightness = 0` so the Fn
# brightness-down key can reach a genuinely black screen. The cost of that is
# that a machine put to sleep at 0 would wake up to a black panel with no
# obvious way back. This puts the old 5% floor -- the value SwayOSD used to
# enforce -- back whenever the session resumes.
#
# Called from:
#   hypr/hypridle.conf        after_sleep_cmd, and the 300 s listener's
#                             on-resume (the locked-but-not-yet-suspended gap)
#   hypr/config/autostart.lua session start, so a reboot or a compositor crash
#                             at 0 does not come back black
#
# RAISE ONLY. It must never lower a brightness that was deliberately set high,
# because it runs on every resume and would otherwise fight the user.

set -u

BL=/sys/class/backlight/intel_backlight
FLOOR_PCT=${1:-5}

# Exit 0, not 1, when there is no backlight to speak of. This runs inside
# hypridle's after_sleep_cmd, which is chained with && -- a non-zero exit here
# would stop whatever follows it and could break waking the screen.
[[ -r "$BL/brightness" && -r "$BL/max_brightness" ]] || exit 0

curr=$(< "$BL/brightness")
max=$(< "$BL/max_brightness")

(( max > 0 )) || exit 0

floor=$(( max * FLOOR_PCT / 100 ))

# Idempotent: at or above the floor, do nothing at all and write nothing.
(( curr >= floor )) && exit 0

brightnessctl --quiet set "${FLOOR_PCT}%"
