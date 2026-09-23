#!/bin/bash

# NOTE: `hyprctl keyword` no longer works under the Lua config manager
# ("keyword can't work with non-legacy parsers. Use eval."), so each former
# --batch keyword string is now a single `hyprctl eval` with one hl.config table.
#
# The old scripts set `misc:vfr`, which does not exist on this Hyprland
# (`hyprctl getoption misc:vfr` -> "no such option"). Variable frame rate lives
# at `debug:vfr` now, so those calls had been silently doing nothing.

if [ -z "$1" ]; then
    echo "Usage: $0 {power|balanced|performance}"
    exit 1
fi

MODE=$1

# The echoes below go nowhere: this runs from rofi (profile-menu.sh) and from
# the waybar module, neither of which has a terminal attached -- so switching
# profiles gave no sign at all that anything had happened. Each case fills these
# in and one notification goes out at the end, once the change has been made.
# Icons per task, like the rest of the notifications (see swaync/README.md).
ICON="" TITLE="" BODY="" PROFILE_RC=0

case $MODE in
    power)
        echo "Activating Ultra Power Saving Mode..."
        powerprofilesctl set power-saver || PROFILE_RC=$?
        ICON=power-profile-power-saver-symbolic
        TITLE="Power Saving"
        BODY="Animations, shadows and blur off; frame rate throttled when idle."

        # Maximize battery: disable eye-candy and enable Variable Frame Rate
        hyprctl eval 'hl.config({
            animations = { enabled = false },
            decoration = {
                shadow = { enabled = false },
                blur   = { enabled = false },
            },
            debug = { vfr = true },
        })'
        ;;

    balanced)
        echo "Activating Balanced Mode..."
        powerprofilesctl set balanced || PROFILE_RC=$?
        ICON=power-profile-balanced-symbolic
        TITLE="Balanced"
        BODY="Animations, shadows and blur back on."

        # Restore normal desktop experience
        hyprctl eval 'hl.config({
            animations = { enabled = true },
            decoration = {
                shadow = { enabled = true },
                blur   = { enabled = true },
            },
            debug = { vfr = true },
        })'
        ;;

    performance)
        echo "Activating Ultra Performance Mode..."
        powerprofilesctl set performance || PROFILE_RC=$?
        ICON=power-profile-performance-symbolic
        TITLE="Ultra Performance"
        BODY="Eye-candy off, frame rate uncapped."

        # Maximize resources for applications/games
        hyprctl eval 'hl.config({
            animations = { enabled = false },
            decoration = {
                shadow = { enabled = false },
                blur   = { enabled = false },
            },
            debug = { vfr = false },
        })'
        ;;

    *)
        echo "Invalid option. Usage: $0 {power|balanced|performance}"
        exit 1
        ;;
esac

# Tell Waybar to refresh its power-profile module now. It no longer polls,
# so without this the icon would sit stale until the hourly fallback tick.
pkill -SIGRTMIN+9 waybar

# The Hyprland side always applied; say so plainly when only the system profile
# refused, rather than claiming a switch that half happened.
if (( PROFILE_RC != 0 )); then
    BODY="Hyprland switched, but power-profiles-daemon refused the system profile."
fi
notify-send -a "Power Profile" -i "$ICON" "$TITLE" "$BODY"
