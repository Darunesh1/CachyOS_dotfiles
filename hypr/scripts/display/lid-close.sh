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

pidof hyprlock >/dev/null || hyprlock &
systemctl suspend
