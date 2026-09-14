#!/usr/bin/env bash

# Hotspot menu (SUPER + CTRL + H, or click the waybar hotspot icon).
#
# Turn the hotspot on/off, and edit its name and password. Settings are kept in
# ~/.config/hotspot.conf by hotspot.sh (never in the repo). Changing them while
# the hotspot is running restarts it with the new values, so devices reconnect
# using them.

DIR="$(dirname "$(readlink -f "$0")")"
HOTSPOT="$DIR/hotspot.sh"
HOTSPOT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hotspot.conf"
THEME="$HOME/.config/rofi/themes/powermenu.rasi"

notify() { notify-send "Hotspot" "$@"; }

# First run creates the file with defaults (random password); then read it.
[[ -f "$HOTSPOT_CONF" ]] || "$HOTSPOT" init
# shellcheck source=/dev/null
source "$HOTSPOT_CONF"

save() {
    ( umask 077
      printf '# Hotspot settings -- edit from the hotspot menu (SUPER + CTRL + H).\n'  > "$HOTSPOT_CONF"
      printf 'HOTSPOT_NAME=%q\nHOTSPOT_PASSWORD=%q\n' "$HOTSPOT_NAME" "$HOTSPOT_PASSWORD" >> "$HOTSPOT_CONF" )
    if [[ "$("$HOTSPOT" status)" == on ]]; then
        notify "Restarting the hotspot with the new settings…"
        "$HOTSPOT" restart
    fi
}

if [[ "$("$HOTSPOT" status)" == on ]]; then
    power="󰀂  Turn hotspot OFF"
else
    power="󰀂  Turn hotspot ON"
fi
name_row="󰏫  Name: $HOTSPOT_NAME"
pass_row="󰌾  Password: ••••••••"
show_row="󰈈  Show password"

choice=$(printf '%s\n' "$power" "$name_row" "$pass_row" "$show_row" \
    | rofi -dmenu -i -no-custom -p "󰀂  Hotspot" -theme "$THEME")

case "$choice" in
    "$power")
        "$HOTSPOT" toggle
        ;;

    "$name_row")
        # -filter pre-fills the box with the current name; an empty list means
        # whatever is typed is returned on Enter. Escape returns nothing.
        new=$(rofi -dmenu -p "New hotspot name" -filter "$HOTSPOT_NAME" -theme "$THEME" </dev/null)
        [[ -z "$new" || "$new" == "$HOTSPOT_NAME" ]] && exit 0
        if (( ${#new} > 32 )); then
            notify -u critical "Name too long" "A Wi-Fi name can be at most 32 characters."
            exit 1
        fi
        HOTSPOT_NAME=$new
        save
        notify "Name changed" "$HOTSPOT_NAME"
        ;;

    "$pass_row")
        # -password hides what is typed.
        new=$(rofi -dmenu -password -p "New password (8-63 characters)" -theme "$THEME" </dev/null)
        [[ -z "$new" ]] && exit 0
        if (( ${#new} < 8 || ${#new} > 63 )); then
            notify -u critical "Password not changed" "WPA2 needs 8-63 characters; that was ${#new}."
            exit 1
        fi
        if [[ "$new" =~ [^[:print:]] ]]; then
            notify -u critical "Password not changed" "Use printable characters only."
            exit 1
        fi
        HOTSPOT_PASSWORD=$new
        save
        notify "Password changed"
        ;;

    "$show_row")
        notify "Name: $HOTSPOT_NAME" "Password: $HOTSPOT_PASSWORD"
        ;;
esac
