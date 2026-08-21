#!/usr/bin/env bash

# Cross-workspace window switcher (SUPER + TAB).
#
# Driven by `hyprctl clients` rather than rofi's own `window` mode. rofi 2.0.0
# can enumerate windows over wlr-foreign-toplevel and Hyprland does export that
# protocol, so `rofi -show window` would work -- but the protocol carries no
# workspace information, and knowing *where* a window is is most of the point of
# a cross-workspace switcher.
#
# The selection is resolved by ROW INDEX (-format i), never by the displayed
# text. Several kitty windows with identical titles are routine here, and
# matching on the label would pick the wrong one.

THEME="$HOME/.config/rofi/themes/windows.rasi"

json=$(hyprctl clients -j 2>/dev/null)
if [[ -z "$json" ]]; then
    notify-send -u critical "Window switcher" "Could not talk to Hyprland"
    exit 1
fi

# ONE snapshot feeds both the labels and the address lookup. Two hyprctl calls
# could disagree if a window opened or closed between them, and the index would
# then point at the wrong window.
mapfile -t rows < <(
    jq -r '
        [ .[] | select(.mapped == true) ]
        | sort_by(
            (if .workspace.id < 0 then 10000 else .workspace.id end),
            (.class // ""),
            (.title // "")
          )
        | .[]
        | [ (if ((.workspace.name // "") | startswith("special"))
             then "S"
             else (.workspace.id | tostring) end),
            (.class // "?"),
            (.title // ""),
            .address ]
        | @tsv
    ' <<<"$json"
)

if [[ ${#rows[@]} -eq 0 ]]; then
    notify-send "Window switcher" "No open windows"
    exit 0
fi

addrs=()
for row in "${rows[@]}"; do
    IFS=$'\t' read -r _ _ _ addr <<<"$row"
    addrs+=("$addr")
done

# Built in a function so the NUL bytes go straight down the pipe -- command
# substitution strips NUL, so this cannot be assembled in a variable first.
build_menu() {
    local row ws cls title addr
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r ws cls title addr <<<"$row"
        # rofi's dmenu row-icon protocol: label NUL "icon" US icon-name.
        # The icon name is the window class, which the configured Papirus-Dark
        # theme resolves for real apps and silently skips for anything else.
        printf '%-3s  %-14s %s\0icon\x1f%s\n' "$ws" "$cls" "$title" "${cls,,}"
    done
}

idx=$(build_menu | rofi -dmenu -i -format i -p "󰖯  Windows" -theme "$THEME")

# Empty on Escape; non-numeric if rofi hands back unmatched custom input.
[[ "$idx" =~ ^[0-9]+$ ]] || exit 0

hyprctl dispatch focuswindow "address:${addrs[$idx]}" >/dev/null
