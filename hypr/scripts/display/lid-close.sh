#!/usr/bin/env bash

# What closing the laptop lid does (bound in config/binds.lua).
#
#   nothing plugged in   ->  lock, then suspend  (what it always did)
#   external display in  ->  nothing at all
#
# Nothing at all, deliberately -- not even locking. A plugged-in display mirrors
# eDP-1 by default, so the laptop panel is the source of the picture: locking it
# or powering it down would blank the TV as well, which is exactly when the lid
# is most likely to be shut. The cost is that the panel stays lit inside a closed
# lid; that is the price of a mirror that keeps working.
#
# Unplug the cable and the normal lock-and-suspend is back.

INTERNAL="eDP-1"

# FALLBACK is filtered out. It is the headless placeholder Hyprland 0.56
# creates when the last real monitor goes (src/state/FallbackState.hpp) so the
# session survives; it displays nothing. Counting it as an external display
# would make closing the lid do nothing at all -- no lock, no suspend -- at the
# exact moment there is no screen on, which is the worst time to leave the
# machine awake and unlocked in a bag.
external_connected() {
    hyprctl monitors all -j 2>/dev/null \
        | jq -e --arg int "$INTERNAL" \
            'map(select(.name != $int and .name != "FALLBACK")) | length > 0' >/dev/null
}

external_connected && exit 0

# This used to start hyprlock itself:
#
#     pidof hyprlock >/dev/null || hyprlock &
#
# That line was the bug behind "the screen comes back for a second, then black".
# The `&` backgrounds the WHOLE `||` list, so the script never waited -- it
# called `systemctl suspend` immediately, logind ran hypridle's
# `before_sleep_cmd = loginctl lock-session`, and that started a SECOND
# hyprlock. Both `pidof` guards checked inside the same second, before either
# process was visible to the other, so both passed. One instance then lost the
# session-lock surface and said so:
#
#     onLockFinished called. Seems we got yeeten. Is another lockscreen running?
#
# and the journal showed its twin dying mid-auth beside every `Lid closed.`:
#
#     hyprlock[29809]: pam_unix(hyprlock:auth): conversation failed
#
# Locking is hypridle's job alone now, through `before_sleep_cmd`, which runs
# before EVERY suspend however it was triggered -- so nothing is lost by not
# locking here. hypridle also holds a systemd sleep inhibitor until the session
# reports itself locked (inhibit_sleep defaults to 2 = auto, which resolves to
# SLEEP_INHIBIT_LOCK_NOTIFY because lock_cmd contains "hyprlock",
# before_sleep_cmd contains "lock-session", and this compositor advertises
# hyprland_lock_notifier_v1), so the lock is genuinely up before we sleep.
#
# Upstream hypridle and the JaKooLit and HyDE dotfiles all do it this way: not
# one of them starts a locker from a lid script.
systemctl suspend
