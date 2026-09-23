#!/usr/bin/env bash

SHADER_DIR="$HOME/.config/hypr/shaders"
STATE_FILE="$HOME/.config/hypr/config/active-shader.lua"

if [[ ! -d "$SHADER_DIR" ]]; then
    notify-send -a "Shaders" -i video-display-symbolic "Shader Menu" "Shader directory not found: $SHADER_DIR"
    exit 1
fi

OPTIONS="None\n$(ls -1 "$SHADER_DIR" | grep '\.frag$')"

CHOICE=$(echo -e "$OPTIONS" | rofi -dmenu -i -p "󰏗  Shader" -theme ~/.config/rofi/themes/shader.rasi)

# Applies the shader live, and persists it as Lua for the next Hyprland start.
# `hyprctl keyword` no longer works under the Lua config manager
# ("keyword can't work with non-legacy parsers. Use eval."), so this uses eval.
# An empty string clears the shader; the old "[[EMPTY]]" sentinel was hyprlang-only.
apply_shader() {
    local path="$1"
    hyprctl eval "hl.config({ decoration = { screen_shader = \"${path}\" } })" >/dev/null
    printf 'hl.config({ decoration = { screen_shader = "%s" } })\n' "$path" > "$STATE_FILE"
}

if [[ "$CHOICE" == "None" ]]; then
    # Apply instantly
    apply_shader ""

    # Completely empty the state file
    > "$STATE_FILE"

    notify-send -a "Shaders" -i video-display-symbolic "Hyprland Shaders" "Shader cleared."

elif [[ -n "$CHOICE" ]]; then
    # Apply instantly, and write the Lua the main config will require() on start
    apply_shader "$SHADER_DIR/$CHOICE"

    notify-send -a "Shaders" -i video-display-symbolic "Hyprland Shaders" "Applied: $CHOICE"
fi
