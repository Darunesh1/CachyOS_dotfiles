#!/bin/bash

# Define options
power="󰌪 Power Saving"
balanced="⚖️ Balanced"
performance="󰾆 Ultra Performance"
gamemode="🎮 Game Mode"

# Show rofi menu
selected=$(echo -e "$power\n$balanced\n$performance\n$gamemode" | rofi -dmenu -i -p "Power Profile:" -theme ~/.config/rofi/themes/launcher.rasi)

# Handle selection
case "$selected" in
    "$power")
        ~/.config/hypr/scripts/power/hypr-profile.sh power
        ;;
    "$balanced")
        ~/.config/hypr/scripts/power/hypr-profile.sh balanced
        ;;
    "$performance")
        ~/.config/hypr/scripts/power/hypr-profile.sh performance
        ;;
    "$gamemode")
        ~/.config/hypr/scripts/power/game-mode.sh
        ;;
esac
