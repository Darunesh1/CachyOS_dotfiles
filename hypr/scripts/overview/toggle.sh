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
shut()   { qs kill -c "$CFG" >/dev/null 2>&1; }

case "${1:-toggle}" in
    open)   is_open || launch ;;
    close)  is_open && shut ;;
    toggle) if is_open; then shut; else launch; fi ;;
    *)      echo "usage: ${0##*/} [open|close|toggle]" >&2; exit 2 ;;
esac
exit 0
