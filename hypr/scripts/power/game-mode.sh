#!/bin/bash

# NOTE: `hyprctl keyword` no longer works under the Lua config manager
# ("keyword can't work with non-legacy parsers. Use eval."), so these are now
# single `hyprctl eval` calls. `misc:vfr` did not exist on this Hyprland and was
# silently doing nothing; variable frame rate lives at `debug:vfr`.

STATE_FILE="/tmp/game_mode_state"

# If already enabled → disable it
if [ -f "$STATE_FILE" ]; then
    echo "Disabling Game Mode..."

    powerprofilesctl set balanced
    hyprctl eval 'hl.config({ animations = { enabled = true } })'

    rm "$STATE_FILE"

    notify-send "Game Mode" "Disabled ❌"
    pkill -SIGRTMIN+9 waybar
    exit 0
fi

# Enable Game Mode
echo "Enabling Game Mode..."

# Save state
touch "$STATE_FILE"

# Switch to performance
powerprofilesctl set performance

# Reduce compositor overhead
hyprctl eval 'hl.config({
    animations = { enabled = false },
    decoration = {
        shadow = { enabled = false },
        blur   = { enabled = false },
    },
    debug = { vfr = false },
})'

# Export Mesa optimizations for future apps
export MESA_GLTHREAD=true
export MESA_NO_ERROR=1

notify-send "Game Mode" "Enabled 🎮"
pkill -SIGRTMIN+9 waybar

# Optional: launch something automatically (commented)
# mangohud gamemoderun ryujinx
