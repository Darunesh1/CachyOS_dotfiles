#!/bin/bash

# Power profile menu (SUPER + SHIFT + G, or click the waybar power icon).
# This is the only way into Game Mode -- see game-mode.sh.

SCRIPTS="$(dirname "$(readlink -f "$0")")"

# Define options
power="󰌪 Power Saving"
balanced="⚖️ Balanced"
performance="󰾆 Ultra Performance"
if [[ "$("$SCRIPTS/game-mode.sh" status)" == "on" ]]; then
    gamemode="🎮 Turn off Game Mode"
else
    gamemode="🎮 Game Mode"
fi

# Show rofi menu
selected=$(echo -e "$power\n$balanced\n$performance\n$gamemode" | rofi -dmenu -i -p "Power Profile:" -theme ~/.config/rofi/themes/launcher.rasi)

# Picking a plain profile while Game Mode is on ends Game Mode first, so the
# things it paused (wallpaper cycle, notifications) come back.
leave_game_mode() { "$SCRIPTS/game-mode.sh" off; }

# Handle selection
case "$selected" in
    "$power")
        leave_game_mode
        "$SCRIPTS/hypr-profile.sh" power
        ;;
    "$balanced")
        leave_game_mode
        "$SCRIPTS/hypr-profile.sh" balanced
        ;;
    "$performance")
        leave_game_mode
        "$SCRIPTS/hypr-profile.sh" performance
        ;;
    "$gamemode")
        "$SCRIPTS/game-mode.sh" toggle
        ;;
esac
