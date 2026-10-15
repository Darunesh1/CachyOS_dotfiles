#!/usr/bin/env bash

# Display menu (SUPER + CTRL + D).
#
# Pick how an external monitor or TV is used: mirror the laptop screen, extend
# to the left or right, or run on one screen only.
#
# Plugging a display in mirrors by default -- that is the catch-all rule in
# config/monitors.lua.
#
# Whatever is chosen here then sticks for the rest of the Hyprland session,
# including across an unplug and replug: `hl.monitor` with a specific output
# name stores a rule under that name, and a named rule beats the empty catch-all
# when the connector next appears. Verified on Hyprland 0.56.2 by storing a rule
# for a connector that did not exist yet and then creating it -- the stored rule
# won. That is usually what you want (set the desk monitor to extend once and it
# stays), but it does mean an unfamiliar projector is not guaranteed a mirror.
# `hyprctl reload` is what forgets the choices.
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

# The external's own rule, with and without mirroring.
#
# Two keys are spelled out rather than left to the default, because a monitor
# rule only changes what it names and leaves the rest of the monitor's state
# alone:
#
#   mirror = ""      -- omitting the key keeps a mirror that is already set, so
#                       "Extend" after "Mirror" would stay mirrored.
#   disabled = false -- omitting it keeps a monitor that was switched off, so
#                       "Mirror" or "Extend" after "External/Laptop screen only"
#                       would report success and change nothing on screen.
ext_mirror() {
    printf 'hl.monitor({ output = "%s", mode = "preferred", position = "auto", scale = 1, mirror = "%s", disabled = false })' \
        "$EXT" "$INTERNAL"
}
ext_at() {
    printf 'hl.monitor({ output = "%s", mode = "preferred", position = "%s", scale = 1, mirror = "", disabled = false })' \
        "$EXT" "$1"
}
internal_on='hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1, disabled = false })'
internal_off='hl.monitor({ output = "eDP-1", disabled = true })'

# The rule definitions above come before this check because the check needs
# internal_on: there is a case where the laptop panel is the thing to bring back.
EXT="$(external)"
if [[ -z "$EXT" ]]; then
    # Blind recovery. "External screen only" stores a `disabled = true` rule for
    # eDP-1, and that rule is kept for the rest of the Hyprland session -- so
    # unplugging the cable while in that mode leaves no lit screen at all, and
    # the menu below would have nowhere to draw itself. A keybind still works on
    # a black screen, so SUPER + CTRL + D is the way out: skip the menu and just
    # turn the panel back on.
    if internal_disabled; then
        apply "Laptop screen" "$internal_on" \
            && notify "Laptop screen back on" "The external display was unplugged."
        exit 0
    fi
    notify "No external display" "Plug in an HDMI or USB-C cable first."
    exit 0
fi


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
