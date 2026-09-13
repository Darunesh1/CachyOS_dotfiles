#!/bin/bash

# Define the directory and the interval (in seconds)
WALLPAPER_DIR="$HOME/Pictures/Wallpaper"
INTERVAL=200
SWAYOSD_CSS="$HOME/.config/swayosd/style.css"
OSD_HASH="$(sha256sum "$SWAYOSD_CSS" 2>/dev/null)"

while true; do
    # Find all images in the folder and pick a random one
    IMG=$(find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) | shuf -n 1)
    
    if [[ -z "$IMG" ]]; then
        echo "No wallpapers found in $WALLPAPER_DIR; retrying in ${INTERVAL}s." >&2
        sleep "$INTERVAL"
        continue
    fi

    # Apply the wallpaper with a smooth transition
    if ! awww img "$IMG" --transition-fps 60 --transition-type random --transition-duration 2; then
        echo "awww failed to apply $IMG; skipping theme update." >&2
        sleep "$INTERVAL"
        continue
    fi

    # Point current_wallpaper at what is actually on screen, even if wallust
    # fails below -- hyprlock and rofi read it.
    ln -sf "$IMG" "$WALLPAPER_DIR/current_wallpaper"

    # Run wallust to generate colors from the new wallpaper
    if ! wallust run "$IMG"; then
        echo "wallust failed for $IMG; keeping the previous theme." >&2
        sleep "$INTERVAL"
        continue
    fi

    # Hyprland re-reads config/wallust.lua for the border colours. Waybar is
    # NOT restarted: reload_style_on_change makes it swap in the regenerated
    # style/wallust.css by itself.
    hyprctl reload >/dev/null 2>&1 || true

    # ── RELOAD SEQUENCE ─────────────────────────────────────────────────────
    # swayosd-server reads its CSS once at startup, so it has to be restarted to
    # pick up the colours wallust just regenerated. Only do that when the file
    # actually changed -- otherwise this bounced the daemon every cycle for
    # nothing. SIGTERM (pkill) rather than killall, so it exits cleanly.
    if [[ "$(sha256sum "$SWAYOSD_CSS" 2>/dev/null)" != "$OSD_HASH" ]]; then
        OSD_HASH="$(sha256sum "$SWAYOSD_CSS" 2>/dev/null)"
        pkill -x swayosd-server
        setsid swayosd-server >/dev/null 2>&1 </dev/null &
    fi
    # ────────────────────────────────────────────────────────────────────────

    # Wait for the specified interval before changing again
    sleep $INTERVAL
done
