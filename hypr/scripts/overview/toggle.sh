#!/usr/bin/env bash
#
# Open, close or toggle the workspace overview (quickshell/overview).
#
#   toggle.sh          open it, or close it if it is already open
#   toggle.sh open     open it; does nothing if it is already open
#   toggle.sh close    close it; does nothing if it is not open
#
# Called from the 3-finger swipe in hypr/config/input.lua and from SUPER + O.
#
# The overview is started on demand and exits when closed, so it costs no RAM
# while you are not looking at it. `-n` makes a second open a no-op rather than
# stacking two overlays, and `-d` detaches it so this script returns at once.
#
# It runs as a separate process on purpose: a bug in it can close the overview
# but cannot take the session down. See
# decisions/0007-workspace-overview-in-quickshell.md.

set -u

CFG=overview

is_open() {
    qs list -c "$CFG" -j 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1
}

# qs prints its own INFO lines ("Launching config", "Killed <id>"). Nothing reads
# them when this runs from a gesture or a keybind, so they are dropped.
launch() { qs -c "$CFG" -d -n >/dev/null 2>&1; }

# Closing asks the overview to close ITSELF, so it plays its exit animation (it
# sinks back down the way it rose). Killing it would just make it vanish.
#
# A hung overview holding the keyboard must ALWAYS be possible to get rid of, and
# the polite routes do not work on a wedged process, which is what this guards:
#
#   * `timeout 1` alone only sends SIGTERM and then waits, and a stopped or hung
#     process never answers it. Measured: with the overview frozen (SIGSTOP) the
#     first version of this took 31 SECONDS and left it alive.
#   * `qs kill` is also a polite signal, so it cannot kill a stopped process.
#
# So: ask over IPC with a hard time limit (`-k` follows SIGTERM with SIGKILL), give
# the animation time to finish, and if the process is still there, SIGKILL it by pid.
shut() {
    local pid i
    pid=$(qs list -c "$CFG" -j 2>/dev/null | jq -r '.[0].pid // empty')
    [[ -n "$pid" ]] || return 0

    if timeout -k 0.3 1 qs ipc -c "$CFG" call overview close >/dev/null 2>&1; then
        for i in 1 2 3 4 5 6 7 8; do
            sleep 0.1
            kill -0 "$pid" 2>/dev/null || return 0
        done
    fi

    # It did not answer, or did not leave. Escalate.
    kill -TERM "$pid" 2>/dev/null
    sleep 0.3
    kill -KILL "$pid" 2>/dev/null
    return 0
}

case "${1:-toggle}" in
    open)   is_open || launch ;;
    close)  is_open && shut ;;
    toggle) if is_open; then shut; else launch; fi ;;
    *)      echo "usage: ${0##*/} [open|close|toggle]" >&2; exit 2 ;;
esac
exit 0
