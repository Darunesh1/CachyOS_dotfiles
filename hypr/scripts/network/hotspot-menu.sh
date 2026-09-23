#!/usr/bin/env bash

# Hotspot menu (SUPER + CTRL + H, or click the waybar hotspot icon).
#
# Turn the hotspot on/off, and edit its name and password. Settings are kept in
# ~/.config/hotspot.conf by hotspot.sh (never in the repo). Changing them while
# the hotspot is running restarts it with the new values, so devices reconnect
# using them.
#
# The name/password prompts are rofi with no list, just an input line -- which
# on its own renders as a thin, easy-to-miss strip with a "Type to filter"
# placeholder. PROMPT_STYLE turns it into a proper dialog: wider, a real
# placeholder, and a message line explaining what to type and how to save.

DIR="$(dirname "$(readlink -f "$0")")"
HOTSPOT="$DIR/hotspot.sh"
HOTSPOT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hotspot.conf"
THEME="$HOME/.config/rofi/themes/powermenu.rasi"

# "Hotspot" as the app name, not as the summary: with it as the summary,
# notify() <title> <body> passed notify-send three positional arguments and it
# refused the whole thing with "Invalid number of options" -- so the on/off and
# password notifications never appeared.
notify() { notify-send -a "Hotspot" -i network-wireless-hotspot-symbolic "$@"; }

# First run creates the file with defaults (random password); then read it.
[[ -f "$HOTSPOT_CONF" ]] || "$HOTSPOT" init
# shellcheck source=/dev/null
source "$HOTSPOT_CONF"

# prompt <title> <placeholder> <message> [extra rofi args...] -> typed text
prompt() {
    local title=$1 placeholder=$2 message=$3
    shift 3
    rofi -dmenu -p "$title" -mesg "$message" -theme "$THEME" \
        -theme-str "window { width: 620px; }
                    mainbox { children: [ inputbar, message ]; }
                    inputbar { border-radius: 12px 12px 0 0; }
                    entry { placeholder: \"$placeholder\"; }
                    message { padding: 10px 14px; }
                    textbox { text-color: @fg1; }" \
        "$@" </dev/null
}

save() {
    ( umask 077
      printf '# Hotspot settings -- edit from the hotspot menu (SUPER + CTRL + H).\n'  > "$HOTSPOT_CONF"
      printf 'HOTSPOT_NAME=%q\nHOTSPOT_PASSWORD=%q\n' "$HOTSPOT_NAME" "$HOTSPOT_PASSWORD" >> "$HOTSPOT_CONF" )
    if [[ "$("$HOTSPOT" status)" == on ]]; then
        notify "Restarting the hotspot with the new settings…"
        "$HOTSPOT" restart
    fi
}

# Status line on top, so you know before trying whether it can start.
if [[ "$("$HOTSPOT" status)" == on ]]; then
    power="󰀂  Turn hotspot OFF"
    status="Hotspot is ON  ·  $HOTSPOT_NAME"
else
    power="󰀂  Turn hotspot ON"
    IFS='|' read -r ok detail <<<"$("$HOTSPOT" check)"
    if [[ "$ok" == ok ]]; then
        status="Hotspot is off  ·  ready to share ($detail)"
    else
        status="Hotspot is off  ·  can't share right now:
$detail"
    fi
fi
name_row="󰏫  Name: $HOTSPOT_NAME"
pass_row="󰌾  Change password"
show_row="󰈈  Show password"

choice=$(printf '%s\n' "$power" "$name_row" "$pass_row" "$show_row" \
    | rofi -dmenu -i -no-custom -p "󰀂  Hotspot" -mesg "$status" -theme "$THEME" \
        -theme-str 'window { width: 560px; } mainbox { children: [ inputbar, message, listview ]; } message { padding: 8px 14px; } textbox { text-color: @fg1; }')

case "$choice" in
    "$power")
        "$HOTSPOT" toggle
        ;;

    "$name_row")
        # -filter pre-fills the box with the current name.
        new=$(prompt "󰏫  Hotspot name" "Type the new hotspot name" \
            "Current name: $HOTSPOT_NAME   ·   1-32 characters   ·   Enter to save, Esc to cancel" \
            -filter "$HOTSPOT_NAME")
        [[ -z "$new" || "$new" == "$HOTSPOT_NAME" ]] && exit 0
        if (( ${#new} > 32 )); then
            notify "Name not changed" "A Wi-Fi name can be at most 32 characters; that was ${#new}."
            exit 1
        fi
        HOTSPOT_NAME=$new
        save
        notify "Name changed" "The hotspot is now called: $HOTSPOT_NAME"
        ;;

    "$pass_row")
        new=$(prompt "󰌾  New password" "Type the new password" \
            "8-63 characters   ·   typing is hidden   ·   Enter to save, Esc to cancel" \
            -password)
        [[ -z "$new" ]] && exit 0
        if (( ${#new} < 8 || ${#new} > 63 )); then
            notify "Password not changed" "WPA2 needs 8-63 characters; that was ${#new}."
            exit 1
        fi
        if [[ "$new" =~ [^[:print:]] ]]; then
            notify "Password not changed" "Use printable characters only."
            exit 1
        fi
        HOTSPOT_PASSWORD=$new
        save
        # Typing was hidden, so show what was saved -- a typo is caught now,
        # not when the phone refuses to connect.
        notify "Password changed" "New password: $HOTSPOT_PASSWORD"
        ;;

    "$show_row")
        notify "Name: $HOTSPOT_NAME" "Password: $HOTSPOT_PASSWORD"
        ;;
esac
