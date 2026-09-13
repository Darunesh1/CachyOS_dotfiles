#!/usr/bin/env bash

# Wallpaper picker (SUPER + CTRL + W): a rofi grid of thumbnails.
#
# rofi decoding ~150 full-size (often 4K) images on every open is slow, so each
# wallpaper gets a 480x270 thumbnail in THUMB_DIR, named by its mtime and file
# name -- a replaced or edited image gets a fresh one, and thumbnails of
# deleted images are pruned. Missing ones are made in parallel before the menu
# opens; after the first run opening is instant.
#
# Picking an image pauses awww-cycle.sh (see PAUSE_FILE there) so the choice
# sticks; the first row, "Random", resumes cycling and applies one right away.
#
# The selection is resolved by ROW INDEX (-format i), never by label text,
# the same as window-switcher.sh.

WALLPAPER_DIR="$HOME/Pictures/Wallpaper"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-thumbs"
THEME="$HOME/.config/rofi/themes/wallpaper.rasi"
PAUSE_FILE="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-cycle-paused"
SET_WALLPAPER="$(dirname "$(readlink -f "$0")")/set-wallpaper.sh"

mkdir -p "$THUMB_DIR"

mapfile -t images < <(
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort
)
if [[ ${#images[@]} -eq 0 ]]; then
    notify-send "Wallpaper" "No images in $WALLPAPER_DIR"
    exit 1
fi

# ── Thumbnails ─────────────────────────────────────────────────────────────
# One stat call for every mtime -- a hash per file meant ~150 subprocesses.
thumbs=()
todo=()
declare -A keep
mapfile -t mtimes < <(stat -c %Y -- "${images[@]}")
for i in "${!images[@]}"; do
    name="${mtimes[$i]}_$(basename "${images[$i]}").jpg"
    thumb="$THUMB_DIR/$name"
    thumbs+=("$thumb")
    keep["$name"]=1
    [[ -s "$thumb" ]] || todo+=("${images[$i]}"$'\t'"$thumb")
done

if [[ ${#todo[@]} -gt 0 ]]; then
    notify-send "Wallpaper" "Generating ${#todo[@]} thumbnail(s)…"
    # Fill-and-crop to 16:9 so every tile in the grid is the same shape.
    # "[0]" takes the first frame/layer only, and is cheap for plain images.
    printf '%s\n' "${todo[@]}" | xargs -P "$(nproc)" -d '\n' -I{} bash -c '
        IFS=$'"'"'\t'"'"' read -r src dst <<<"$1"
        magick "${src}[0]" -thumbnail 480x270^ -gravity center -extent 480x270 \
            -quality 85 "$dst" 2>/dev/null
    ' _ {}
fi

for f in "$THUMB_DIR"/*.jpg; do
    [[ -e "$f" ]] || continue
    [[ -n "${keep[$(basename "$f")]:-}" ]] || rm -f "$f"
done

# ── Menu ───────────────────────────────────────────────────────────────────
current="$(readlink -f "$WALLPAPER_DIR/current_wallpaper" 2>/dev/null)"
selected=0
for i in "${!images[@]}"; do
    [[ "${images[$i]}" == "$current" ]] && selected=$((i + 1)) && break
done

build_menu() {
    # Row 0: resume random cycling. The icon is the current wallpaper, if any.
    printf '󰑓  Random (resume auto-cycle)\0icon\x1f%s\n' "${thumbs[$((selected > 0 ? selected - 1 : 0))]}"
    local i name
    for i in "${!images[@]}"; do
        name="$(basename "${images[$i]}")"
        printf '%s\0icon\x1f%s\n' "${name%.*}" "${thumbs[$i]}"
    done
}

idx=$(build_menu | rofi -dmenu -i -no-custom -show-icons -format i \
    -selected-row "$selected" -p "󰸉  Wallpaper" -theme "$THEME")

# Empty on Escape.
[[ "$idx" =~ ^[0-9]+$ ]] || exit 0

if [[ "$idx" -eq 0 ]]; then
    rm -f "$PAUSE_FILE"
    img="${images[RANDOM % ${#images[@]}]}"
    notify-send "Wallpaper" "Auto-cycle resumed"
else
    touch "$PAUSE_FILE"
    img="${images[$((idx - 1))]}"
fi

exec "$SET_WALLPAPER" "$img"
