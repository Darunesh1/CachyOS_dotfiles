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
# once (a crashed session leaves its own behind), and the glob order is lexical
# on a hashed name, which is meaningless.
#
# BUT newest-by-mtime alone was a bug (2026-11-07 to 2026-11-09): this script
# runs on hyprland.start, when the session just STARTING already owns the
# newest log. So it saved the current session's first few hundred lines instead
# of the previous session's whole log -- twelve consecutive saves of ~19,455
# bytes, every one ending in "Starting the Aquamarine backend!". The one useful
# 498,626-byte copy came from running this by hand mid-session.
#
# Excluding $HYPRLAND_INSTANCE_SIGNATURE is the fix: that is the directory name
# of the session we are running inside.
prev=$(ls -t /run/user/"$(id -u)"/hypr/*/hyprland.log 2>/dev/null \
    | grep -v "/${HYPRLAND_INSTANCE_SIGNATURE:-__no_such_instance__}/" \
    | head -1)

# Nothing to copy is normal, not an error -- this runs on a fresh boot too.
[[ -n "$prev" && -r "$prev" ]] || exit 0

# A log this small is a session that had barely started, which is the signature
# of the bug above. Refuse it loudly rather than overwrite a good copy.
prev_size=$(stat -c %s "$prev" 2>/dev/null || echo 0)
if (( prev_size < 32768 )); then
    printf '%s REFUSED %s (%s bytes, under 32K -- looks like a just-started session)\n' \
        "$(date -Is)" "$prev" "$prev_size" \
        >>"$STATE/save-prev-log.log" 2>/dev/null || true
    exit 0
fi

cp -- "$prev" "$STATE/hyprland-prev.log" 2>/dev/null || exit 0
printf '%s saved %s (%s bytes)\n' "$(date -Is)" "$prev" "$(stat -c %s "$STATE/hyprland-prev.log")" \
    >>"$STATE/save-prev-log.log" 2>/dev/null || true
