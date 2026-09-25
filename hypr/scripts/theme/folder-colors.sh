#!/usr/bin/env bash

# Folder icons that follow the wallpaper.
#
#   folder-colors.sh [#rrggbb]
#
# With no argument the accent comes from wallust's own output
# (~/.config/zsh/wallust-colors.zsh, WALLUST_ACCENT). set-wallpaper.sh calls
# this right after `wallust run`.
#
# Papirus already ships ~25 folder colour sets -- folder-teal.svg,
# folder-orange.svg and so on, with folder.svg a plain symlink to
# folder-blue.svg. So nothing is generated here: the nearest shipped colour to
# the accent is picked and a small icon theme of SYMLINKS into Papirus is built
# at ~/.local/share/icons/wallust-papirus. No copying (Papirus-Dark is 33 MB),
# no root, and it survives a Papirus update because it points at the files
# rather than editing them -- which is what papirus-folders does, and why that
# tool needs sudo on every run.
#
# The candidate colours are not hardcoded: any folder-<name>.svg that also has
# a folder-<name>-documents.svg is a colour set (the rest are special folders
# like folder-music.svg), and its fill is read out of the SVG. A Papirus update
# that adds a colour is picked up by itself.
#
# The theme NAME never changes, only its contents. That matters: there is no
# XSettings daemon under Hyprland, so GTK apps read gtk-icon-theme-name once at
# startup -- but GTK does watch the icon theme's directory and reloads when the
# files under it change. Renaming the theme per wallpaper would need every GTK
# app restarted.

set -u

SRC="/usr/share/icons/Papirus-Dark"
DEST="$HOME/.local/share/icons/wallust-papirus"
THEME_NAME="wallust-papirus"
WALLUST_COLORS="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/wallust-colors.zsh"
GTK3_INI="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"

[[ -d "$SRC" ]] || { echo "folder-colors: $SRC not found (papirus-icon-theme)" >&2; exit 1; }

# ── The accent ──────────────────────────────────────────────────────────────
accent="${1:-}"
if [[ -z "$accent" ]]; then
    # Grepped, not sourced: that file is zsh (typeset -gA, hooks) and would
    # not survive being read by bash.
    accent=$(sed -nE 's/^export WALLUST_ACCENT="(#[0-9a-fA-F]{6})".*/\1/p' "$WALLUST_COLORS" 2>/dev/null | head -1)
fi
if [[ ! "$accent" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    echo "folder-colors: no accent colour (looked in $WALLUST_COLORS)" >&2
    exit 1
fi

# ── Nearest shipped colour ──────────────────────────────────────────────────
# Redmean distance rather than plain RGB: it is still one line of arithmetic,
# but it does not call a dark red and a dark blue "close" the way raw Euclidean
# distance does.
nearest_color() {
    local want=$1 c f fill
    for f in "$SRC"/64x64/places/folder-*.svg; do
        c=${f##*/}; c=${c#folder-}; c=${c%.svg}
        [[ "$c" == *-* ]] && continue
        [[ -e "$SRC/64x64/places/folder-$c-documents.svg" ]] || continue
        fill=$(grep -oE '#[0-9a-fA-F]{6}' "$f" | head -1) || continue
        [[ -n "$fill" ]] && printf '%s %s\n' "$c" "$fill"
    done | awk -v want="$want" '
        function hex(s, p) { return strtonum("0x" substr(s, p, 2)) }
        BEGIN {
            wr = hex(want, 2); wg = hex(want, 4); wb = hex(want, 6)
            best = ""; bestd = -1
        }
        {
            r = hex($2, 2); g = hex($2, 4); b = hex($2, 6)
            rm = (wr + r) / 2
            dr = wr - r; dg = wg - g; db = wb - b
            d = (2 + rm/256)*dr*dr + 4*dg*dg + (2 + (255-rm)/256)*db*db
            if (bestd < 0 || d < bestd) { bestd = d; best = $1 }
        }
        END { print best }
    '
}

color=$(nearest_color "$accent")
[[ -n "$color" ]] || { echo "folder-colors: no colour sets found in $SRC" >&2; exit 1; }

# ── Build the theme ─────────────────────────────────────────────────────────
# Rebuilt from scratch each time: a colour switch leaves no stale links behind,
# and a few hundred symlinks cost nothing to recreate.
tmp="$DEST.new.$$"
rm -rf -- "$tmp"
mkdir -p "$tmp"

dirs=()
for d in "$SRC"/*/places; do
    [[ -e "$d/folder-$color.svg" ]] || continue
    size=$(basename "$(dirname "$d")")       # 64x64, 16x16@2x, ...
    mkdir -p "$tmp/$size/places"
    dirs+=("$size/places")
    # folder-teal.svg -> folder.svg, folder-teal-documents.svg ->
    # folder-documents.svg, user-teal-home.svg -> user-home.svg. The special
    # folders matter: without them Documents and Downloads would stay blue
    # while everything around them changed.
    for f in "$d"/folder-"$color".svg "$d"/folder-"$color"-*.svg "$d"/user-"$color"-*.svg; do
        [[ -e "$f" ]] || continue
        base=${f##*/}
        case "$base" in
            folder-"$color".svg)    link="folder.svg" ;;
            folder-"$color"-*)      link="folder-${base#folder-$color-}" ;;
            user-"$color"-*)        link="user-${base#user-$color-}" ;;
            *) continue ;;
        esac
        ln -sfn "$f" "$tmp/$size/places/$link"
    done
done

if ((${#dirs[@]} == 0)); then
    rm -rf -- "$tmp"
    echo "folder-colors: $SRC has no size holding folder-$color.svg" >&2
    exit 1
fi

{
    printf '[Icon Theme]\n'
    printf 'Name=%s\n' "$THEME_NAME"
    printf 'Comment=Papirus folders recoloured to the wallpaper (generated -- see hypr/scripts/theme/folder-colors.sh)\n'
    printf 'Inherits=Papirus-Dark,Papirus,Adwaita,hicolor\n'
    printf 'Directories=%s\n' "$(IFS=,; echo "${dirs[*]}")"
    for d in "${dirs[@]}"; do
        size=${d%%/*}                       # 64x64 or 16x16@2x
        scale=1
        [[ "$size" == *@* ]] && { scale=${size##*@}; scale=${scale%x}; size=${size%@*}; }
        printf '\n[%s]\n' "$d"
        printf 'Size=%s\n' "${size%%x*}"
        printf 'Scale=%s\n' "$scale"
        printf 'Context=Places\n'
        printf 'Type=Fixed\n'
    done
} > "$tmp/index.theme"

# Swap in one move so no GTK app ever sees a half-built theme.
rm -rf -- "$DEST.old"
[[ -d "$DEST" ]] && mv -- "$DEST" "$DEST.old"
mv -- "$tmp" "$DEST"
rm -rf -- "$DEST.old"

# ── Point GTK at it (idempotent; only needed the first time) ────────────────
mkdir -p "$(dirname "$GTK3_INI")"
if ! grep -q "^gtk-icon-theme-name=$THEME_NAME$" "$GTK3_INI" 2>/dev/null; then
    if grep -q '^gtk-icon-theme-name=' "$GTK3_INI" 2>/dev/null; then
        sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$THEME_NAME/" "$GTK3_INI"
    else
        [[ -f "$GTK3_INI" ]] || printf '[Settings]\n' > "$GTK3_INI"
        sed -i "0,/^\[Settings\]$/s//[Settings]\ngtk-icon-theme-name=$THEME_NAME/" "$GTK3_INI"
    fi
fi
command -v gsettings >/dev/null && \
    gsettings set org.gnome.desktop.interface icon-theme "$THEME_NAME" 2>/dev/null

echo "folder-colors: $accent -> $color"
