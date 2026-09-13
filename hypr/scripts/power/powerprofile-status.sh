#!/bin/bash

profile=$(powerprofilesctl get)

if [ -f "${XDG_RUNTIME_DIR:-/tmp}/game-mode/active" ]; then
    icon="🎮"
    text="Game Mode (performance + scx gaming)"
    sched=$(scxctl get 2>/dev/null)
    [[ -n "$sched" && "$sched" != *"no scx scheduler"* ]] && text="$text\\n$sched"
elif [ "$profile" = "power-saver" ]; then
    icon="󰌪"
    text="Ultra Power Saving"
elif [ "$profile" = "balanced" ]; then
    icon="⚖️"
    text="Balanced"
elif [ "$profile" = "performance" ]; then
    icon="󰾆"
    text="Ultra Performance"
else
    icon="󰁾"
    text="Unknown"
fi

# Output JSON for Waybar
echo "{\"text\": \"$icon\", \"tooltip\": \"$text\"}"
