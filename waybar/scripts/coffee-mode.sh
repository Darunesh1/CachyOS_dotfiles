#!/usr/bin/env bash

# Toggle "coffee mode": pause hypridle so the screen never locks or suspends.
#
# This used to send SIGUSR1 to pause and SIGUSR2 to resume. hypridle installs no
# handler for either, and the default disposition of SIGUSR1 is to TERMINATE the
# process -- so turning coffee mode on killed the daemon outright, and turning it
# off signalled a process that no longer existed. Idle locking and idle-suspend
# stayed dead until the next login, which looked like "sleep is broken".
#
# So stop and start the daemon explicitly instead of pretending to pause it.

STATE_FILE="/tmp/hypridle-paused"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "Coffee Mode" "$1"
}

if [[ -f "$STATE_FILE" ]]; then
    # ── Resume idle handling ────────────────────────────────────────────────
    rm -f "$STATE_FILE"

    if ! pgrep -x hypridle >/dev/null; then
        setsid hypridle >/dev/null 2>&1 </dev/null &

        # Report a failed restart rather than silently leaving idle handling off.
        sleep 1
        pgrep -x hypridle >/dev/null || notify "Failed to restart hypridle"
    fi
else
    # ── Pause idle handling ─────────────────────────────────────────────────
    # SIGTERM, so hypridle releases its sleep inhibitor on the way out.
    pkill -x hypridle
    touch "$STATE_FILE"
fi

# Refresh Waybar immediately
pkill -SIGRTMIN+8 waybar
