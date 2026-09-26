#!/usr/bin/env bash

# Change the login screen's background video and font.
#
#   customise-theme.sh --background ~/Downloads/something.mp4
#   customise-theme.sh --font "Adwaita Sans"
#   customise-theme.sh --layout bottom-left            # move the login prompt
#   customise-theme.sh --background x.mp4 --compress   # re-encode smaller
#   customise-theme.sh --restore                       # back to stock
#
# Two things decide how a qylock theme looks, and neither is the layout:
#
#   bg.mp4   -- BackgroundVideo.qml hardcodes `source: "bg.mp4"`, so the
#               background is whatever file has that name.
#   font/    -- Main.qml builds a FolderListModel over font/, loads the FIRST
#               .ttf/.otf it finds, and all 8 of its text elements use
#               `font.family: pf.name`. Nothing names the font, so replacing
#               that one file restyles every word on the screen.
#
# Everything else -- clock, password field, session and power buttons, the
# drifting specks -- is plain QML with no game artwork in it, which is why the
# layout survives both swaps.
#
# The theme lives under /usr/share because the login screen runs as its own
# user and cannot read $HOME. That is also why this needs sudo, and why the
# login screen cannot follow the desktop wallpaper cycle: every change is a
# deliberate copy, not something a script can do behind you 150 times a day.

set -euo pipefail

THEME_DIR="/usr/share/sddm/themes/pixel-hollowknight"
SECONDS_CAP=30
COMPRESS=0
BACKGROUND=""
FONT=""
LAYOUT=""
RESTORE=0
SELF_DIR="$(dirname "$(readlink -f "$0")")"

usage() { sed -n '3,9p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }

while (( $# )); do
    case "$1" in
        --background|-b) BACKGROUND="${2:?--background needs a file}"; shift 2 ;;
        --font|-f)       FONT="${2:?--font needs a family name or file}"; shift 2 ;;
        --layout|-l)     LAYOUT="${2:?--layout needs a name, e.g. bottom-left}"; shift 2 ;;
        --seconds)       SECONDS_CAP="${2:?--seconds needs a number}"; shift 2 ;;
        --compress)      COMPRESS=1; shift ;;
        --theme)         THEME_DIR="/usr/share/sddm/themes/${2:?--theme needs a name}"; shift 2 ;;
        --restore)       RESTORE=1; shift ;;
        -h|--help)       usage 0 ;;
        *) echo "unknown option: $1" >&2; usage 1 ;;
    esac
done

[[ -d "$THEME_DIR" ]] || { echo "customise-theme: no theme at $THEME_DIR -- run install-theme.sh first" >&2; exit 1; }
[[ -n "$BACKGROUND$FONT$LAYOUT" || $RESTORE -eq 1 ]] || usage 1

note() { printf ':: %s\n' "$*"; }

# ── Restore ─────────────────────────────────────────────────────────────────
if (( RESTORE )); then
    if sudo test -f "$THEME_DIR/bg.mp4.orig"; then
        sudo cp -- "$THEME_DIR/bg.mp4.orig" "$THEME_DIR/bg.mp4"
        note "background restored"
    else
        note "no bg.mp4.orig -- background was never changed"
    fi
    if sudo test -f "$THEME_DIR/Main.qml.orig"; then
        sudo cp -- "$THEME_DIR/Main.qml.orig" "$THEME_DIR/Main.qml"
        note "layout restored"
    else
        note "no Main.qml.orig -- layout was never changed"
    fi
    if sudo test -d "$THEME_DIR/font/.orig"; then
        sudo find "$THEME_DIR/font" -maxdepth 1 -type f -delete
        sudo cp -a "$THEME_DIR"/font/.orig/. "$THEME_DIR/font/"
        note "font restored"
    else
        note "no font/.orig -- font was never changed"
    fi
    exit 0
fi

# ── Background ──────────────────────────────────────────────────────────────
if [[ -n "$BACKGROUND" ]]; then
    [[ -f "$BACKGROUND" ]] || { echo "customise-theme: no such file: $BACKGROUND" >&2; exit 1; }
    command -v ffmpeg >/dev/null || { echo "customise-theme: ffmpeg is needed" >&2; exit 1; }

    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$BACKGROUND" || true)
    width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$BACKGROUND" || true)

    tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
    out="$tmp/bg.mp4"

    if [[ -z "$codec" ]]; then
        # A still image: give it a slow drift so it reads as alive rather than
        # as a frozen desktop.
        note "still image -> 20 s drifting loop"
        ffmpeg -v error -y -loop 1 -i "$BACKGROUND" -t 20 \
            -vf "scale=2400:-2,zoompan=z='min(zoom+0.0004,1.12)':d=500:s=1920x1080:fps=25,format=yuv420p" \
            -c:v libx264 -crf 24 -preset medium -movflags +faststart -an "$out"
    elif (( COMPRESS == 0 )) && [[ "$codec" == "h264" ]] && [[ -n "$width" ]] && (( width <= 1920 )); then
        # Already the right shape. Remuxing keeps every bit of quality, strips
        # the audio and takes a second; re-encoding would only lose detail.
        note "already H.264 at ${width}px -- remuxing (no quality loss), dropping audio"
        ffmpeg -v error -y -i "$BACKGROUND" -c:v copy -an -movflags +faststart "$out"
    else
        note "re-encoding to 1080p30 (h264, crf 26), dropping audio"
        ffmpeg -v error -y -i "$BACKGROUND" -t "$SECONDS_CAP" \
            -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,format=yuv420p" \
            -c:v libx264 -crf 26 -preset medium -movflags +faststart -an "$out"
    fi

    # -an above is the point: a login screen that makes noise is a bug.
    if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$out" | grep -q .; then
        echo "customise-theme: refusing to install -- the result still has audio" >&2
        exit 1
    fi

    sudo test -f "$THEME_DIR/bg.mp4.orig" \
        || sudo cp -- "$THEME_DIR/bg.mp4" "$THEME_DIR/bg.mp4.orig"
    sudo install -Dm644 "$out" "$THEME_DIR/bg.mp4"
    note "background installed: $(du -h "$out" | cut -f1) (was $(sudo du -h "$THEME_DIR/bg.mp4.orig" | cut -f1))"
fi

# ── Font ────────────────────────────────────────────────────────────────────
if [[ -n "$FONT" ]]; then
    if [[ -f "$FONT" ]]; then
        font_file="$FONT"
    else
        command -v fc-match >/dev/null || { echo "customise-theme: fc-match is needed to resolve a family name" >&2; exit 1; }
        font_file=$(fc-match -f '%{file}' "$FONT")
        [[ -f "$font_file" ]] || { echo "customise-theme: no font file for '$FONT'" >&2; exit 1; }
        # fc-match always answers with something; make sure it is not a
        # silent fallback to a completely different family.
        got=$(fc-match -f '%{family[0]}' "$FONT")
        [[ "${got,,}" == "${FONT,,}"* ]] || note "note: '$FONT' resolved to '$got' ($font_file)"
    fi

    sudo test -d "$THEME_DIR/font/.orig" || {
        sudo mkdir -p "$THEME_DIR/font/.orig"
        sudo find "$THEME_DIR/font" -maxdepth 1 -type f -exec cp -- {} "$THEME_DIR/font/.orig/" \;
    }
    # Exactly one file must remain: the theme loads whichever the folder model
    # returns first, and two files would make the result a coin toss.
    sudo find "$THEME_DIR/font" -maxdepth 1 -type f -delete
    sudo install -Dm644 "$font_file" "$THEME_DIR/font/$(basename "$font_file")"
    note "font installed: $(basename "$font_file")"
    note "  (a variable font may render at its default weight -- if it looks"
    note "   wrong, point --font at a static .ttf instead)"
fi

# ── Layout ──────────────────────────────────────────────────────────────────
if [[ -n "$LAYOUT" ]]; then
    patch_file="$SELF_DIR/patches/login-$LAYOUT.patch"
    [[ -f "$patch_file" ]] || { echo "customise-theme: no patch at $patch_file" >&2; exit 1; }
    command -v patch >/dev/null || { echo "customise-theme: patch(1) is needed" >&2; exit 1; }

    # Always patch the pristine file, never the already-patched one: running
    # this twice should be a no-op, not a double application.
    sudo test -f "$THEME_DIR/Main.qml.orig" \
        || sudo cp -- "$THEME_DIR/Main.qml" "$THEME_DIR/Main.qml.orig"

    work=$(mktemp -d); trap 'rm -rf -- "$work"' EXIT
    sudo cat "$THEME_DIR/Main.qml.orig" > "$work/Main.qml"

    # Dry run first. A qylock update that rewrites Main.qml must fail loudly
    # rather than leave a half-applied layout on the login screen.
    if ! patch -s --batch --forward --dry-run -p1 -d "$work" < "$patch_file"; then
        echo "customise-theme: '$LAYOUT' does not apply to this Main.qml." >&2
        echo "  The theme has changed upstream; the patch needs redoing against the new file." >&2
        exit 1
    fi
    patch -s --batch --forward -p1 -d "$work" < "$patch_file"
    sudo install -Dm644 "$work/Main.qml" "$THEME_DIR/Main.qml"
    note "layout applied: $LAYOUT"
fi

echo
echo "Look at it before rebooting, with the real greeter in a window:"
echo "    sddm-greeter-qt6 --test-mode --theme $THEME_DIR"
echo "Undo everything:"
echo "    $0 --restore"
