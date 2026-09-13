#!/bin/bash

# Random wallpaper every INTERVAL seconds, themed via set-wallpaper.sh.
#
# Picking a wallpaper in wallpaper-menu.sh (SUPER + CTRL + W) creates PAUSE_FILE
# so the choice is not replaced on the next tick; picking "Random" there removes
# it. The loop keeps running while paused and just skips the change. The file is
# in the runtime dir, so a new login goes back to cycling.

WALLPAPER_DIR="$HOME/Pictures/Wallpaper"
INTERVAL=200
PAUSE_FILE="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-cycle-paused"
SET_WALLPAPER="$(dirname "$(readlink -f "$0")")/set-wallpaper.sh"

while true; do
    if [[ ! -f "$PAUSE_FILE" ]]; then
        # Find all images in the folder and pick a random one
        IMG=$(find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) | shuf -n 1)

        if [[ -z "$IMG" ]]; then
            echo "No wallpapers found in $WALLPAPER_DIR; retrying in ${INTERVAL}s." >&2
        else
            "$SET_WALLPAPER" "$IMG"
        fi
    fi

    # Wait for the specified interval before changing again
    sleep "$INTERVAL"
done
