#!/usr/bin/env bash
#
# Keep the PREVIOUS session's hyprland.log across a reboot. Run once per
# session from config/autostart.lua, before the new session has written much.
#
# WHY: Hyprland writes to /run/user/$UID/hypr/<instance>/hyprland.log, which is
# tmpfs and dies with the boot. Every time the screen came back black after a
# resume, the machine was rebooted -- which destroyed the only record of what
# happened. This copies it aside so the next occurrence leaves evidence.
#
# One copy is kept, not a rotation: the log reached 1.9 MB in 30 minutes, and
# the question is only ever "what did the session that just broke say".

set -u

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/hypr
mkdir -p "$STATE" 2>/dev/null || exit 0

# Newest by mtime, not a bare glob: several instance directories can exist at
# once (a crashed session leaves its own behind), and the glob order is
# lexical on a hashed name, which is meaningless.
prev=$(ls -t /run/user/"$(id -u)"/hypr/*/hyprland.log 2>/dev/null | head -1)

# Nothing to copy is normal, not an error -- this runs on a fresh boot too.
[[ -n "$prev" && -r "$prev" ]] || exit 0

cp -- "$prev" "$STATE/hyprland-prev.log" 2>/dev/null || exit 0
printf '%s saved %s (%s bytes)\n' "$(date -Is)" "$prev" "$(stat -c %s "$STATE/hyprland-prev.log")" \
    >>"$STATE/save-prev-log.log" 2>/dev/null || true
