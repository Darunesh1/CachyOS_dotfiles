#!/usr/bin/env bash

# Apply one wallpaper and re-theme the desktop from it.
#
#   set-wallpaper.sh <image>
#
# The single place this sequence lives: awww-cycle.sh (random, every 200 s) and
# wallpaper-menu.sh (SUPER + CTRL + W) both call it, so a picked wallpaper and a
# cycled one always end up themed the same way.

WALLPAPER_DIR="$HOME/Pictures/Wallpaper"
SWAYOSD_CSS="$HOME/.config/swayosd/style.css"
OSD_HASH_FILE="${XDG_RUNTIME_DIR:-/tmp}/swayosd-css.sha256"

IMG="$1"
if [[ ! -f "$IMG" ]]; then
    echo "set-wallpaper: not a file: $IMG" >&2
    exit 1
fi

# Apply the wallpaper with a smooth transition
if ! awww img "$IMG" --transition-fps 60 --transition-type random --transition-duration 2; then
    echo "awww failed to apply $IMG; skipping theme update." >&2
    exit 1
fi

# Point current_wallpaper at what is actually on screen, even if wallust
# fails below -- hyprlock and rofi read it.
ln -sf "$IMG" "$WALLPAPER_DIR/current_wallpaper"

# Run wallust to generate colors from the new wallpaper
if ! wallust run "$IMG"; then
    echo "wallust failed for $IMG; keeping the previous theme." >&2
    exit 1
fi

# Re-apply ONLY the three colours wallust just regenerated: the two border
# gradients and the shadow. Waybar is NOT restarted either --
# reload_style_on_change makes it swap in the regenerated style/wallust.css
# by itself.
#
# This used to be a blanket `hyprctl reload`, which re-evaluated every config
# file to pick up two colours. That also re-applied config/monitors.lua, whose
# catch-all rule put an extended display back to mirroring -- and awww-cycle.sh
# calls this script every 200 s, so "Extend" silently reverted within three and
# a half minutes with no user action at all.
#
# Verified that a partial hl.config merges rather than resetting siblings:
# decoration:shadow:range, :rounding, :blur:size and :screen_shader are all
# unchanged across this call.
#
# One behaviour deliberately given up: hand edits to hypr/config/*.lua are no
# longer picked up for free within 200 s. Use SUPER + SHIFT + R (binds.lua).
hyprctl eval 'dofile(os.getenv("HOME") .. "/.config/hypr/config/theme-colors.lua").apply()' \
    >/dev/null 2>&1 || true

# swaync re-reads its stylesheet on request, so unlike swayosd below it never
# has to be restarted -- the notification colours change with the next popup.
swaync-client -rs >/dev/null 2>&1 || true

# Folder icons: pick the nearest Papirus colour to the new accent. GTK watches
# the icon theme directory, so open windows follow without being restarted.
"$(dirname "$(readlink -f "$0")")/../theme/folder-colors.sh" >/dev/null 2>&1 || true

# swayosd-server reads its CSS once at startup, so it has to be restarted to
# pick up the colours wallust just regenerated. Only do that when the file
# actually changed -- the hash is kept in the runtime dir because this script
# no longer lives inside one long-running loop. SIGTERM (pkill) rather than
# killall, so it exits cleanly.
new_hash="$(sha256sum "$SWAYOSD_CSS" 2>/dev/null)"
if [[ "$new_hash" != "$(cat "$OSD_HASH_FILE" 2>/dev/null)" ]]; then
    printf '%s\n' "$new_hash" > "$OSD_HASH_FILE"
    pkill -x swayosd-server
    setsid swayosd-server >/dev/null 2>&1 </dev/null &
fi
