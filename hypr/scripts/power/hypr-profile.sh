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

case $MODE in
    power)
        echo "Activating Ultra Power Saving Mode..."
        powerprofilesctl set power-saver

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
        powerprofilesctl set balanced

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
        powerprofilesctl set performance

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
