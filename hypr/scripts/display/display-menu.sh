#!/usr/bin/env bash

# Display menu (SUPER + CTRL + D).
#
# Pick how an external monitor or TV is used: mirror the laptop screen, extend
# to the left or right, or run on one screen only.
#
# Plugging a display in mirrors by default -- that is the catch-all rule in
# config/monitors.lua, and it is also what a display falls back to when it is
# unplugged and connected again. Whatever is chosen here lasts until then.
#
# Rules are applied with `hyprctl eval`, not `hyprctl keyword`: under the Lua
# config manager keyword refuses with "can't work with non-legacy parsers. Use
# eval." Every eval is checked -- it prints "ok", or a line starting with
# "error:", and a failure that is swallowed looks exactly like a menu that does
# nothing.

INTERNAL="eDP-1"
THEME="$HOME/.config/rofi/themes/powermenu.rasi"

notify() { notify-send -a "Display" -i video-display-symbolic "$@"; }

# `monitors all`, not `monitors`: a display switched off by "Laptop screen only"
# is still connected and has to stay in the list, or there would be no way back.
monitors_json() { hyprctl monitors all -j; }

external() {
    monitors_json | jq -r --arg int "$INTERNAL" \
        'map(select(.name != $int)) | .[0].name // empty'
}

internal_disabled() {
    monitors_json | jq -e --arg int "$INTERNAL" \
        'map(select(.name == $int and .disabled == true)) | length > 0' >/dev/null
}

# apply <what it is called> <lua> [<lua> ...] -- stops at the first failure.
apply() {
    local label=$1 out; shift
    local lua
    for lua in "$@"; do
        out=$(hyprctl eval "$lua" 2>&1)
        if [[ "$out" == error:* ]]; then
            notify "$label failed" "${out#error: }"
            return 1
        fi
    done
    return 0
}

EXT="$(external)"
if [[ -z "$EXT" ]]; then
    notify "No external display" "Plug in an HDMI or USB-C cable first."
    exit 0
fi

# The external's own rule, with and without mirroring. mirror is passed as an
# empty string rather than left out when un-mirroring: a rule that simply omits
# the key may leave the previous mirror in place.
ext_mirror() {
    printf 'hl.monitor({ output = "%s", mode = "preferred", position = "auto", scale = 1, mirror = "%s" })' \
        "$EXT" "$INTERNAL"
}
ext_at() {
    printf 'hl.monitor({ output = "%s", mode = "preferred", position = "%s", scale = 1, mirror = "" })' \
        "$EXT" "$1"
}
internal_on='hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })'
internal_off='hl.monitor({ output = "eDP-1", disabled = true })'

if internal_disabled; then
    status="$EXT connected  ·  external screen only"
else
    mirroring=$(monitors_json | jq -r --arg e "$EXT" 'map(select(.name == $e)) | .[0].disabled')
    if [[ "$mirroring" == true ]]; then
        status="$EXT connected but switched off  ·  laptop screen only"
    else
        status="$EXT connected"
    fi
fi

mirror_row="󰍹  Mirror -- same picture on both"
right_row="󰍺  Extend -- external on the right"
left_row="󰍺  Extend -- external on the left"
laptop_row="󰌢  Laptop screen only"
ext_row="󰟴  External screen only"

choice=$(printf '%s\n' "$mirror_row" "$right_row" "$left_row" "$laptop_row" "$ext_row" \
    | rofi -dmenu -i -no-custom -p "󰍹  Display" -mesg "$status" -theme "$THEME" \
        -theme-str 'window { width: 560px; }
                    mainbox { children: [ inputbar, message, listview ]; }
                    message { padding: 8px 14px; }
                    entry { placeholder: ""; }
                    textbox { text-color: @fg1; }')

case "$choice" in
    "$mirror_row")
        apply "Mirror" "$internal_on" "$(ext_mirror)" \
            && notify "Mirroring" "$EXT shows the same as the laptop screen."
        ;;
    "$right_row")
        apply "Extend" "$internal_on" "$(ext_at auto-right)" \
            && notify "Extended" "$EXT is to the right of the laptop screen."
        ;;
    "$left_row")
        apply "Extend" "$internal_on" "$(ext_at auto-left)" \
            && notify "Extended" "$EXT is to the left of the laptop screen."
        ;;
    "$laptop_row")
        apply "Laptop screen only" "$internal_on" \
            "hl.monitor({ output = \"$EXT\", disabled = true })" \
            && notify "Laptop screen only" "$EXT is switched off."
        ;;
    "$ext_row")
        # Un-mirror first: the mirror's source is the laptop panel, so turning
        # that off while $EXT still mirrors it would leave both screens blank.
        apply "External screen only" "$(ext_at auto)" "$internal_off" \
            && notify "External screen only" "The laptop screen is off. SUPER + CTRL + D brings it back."
        ;;
esac
