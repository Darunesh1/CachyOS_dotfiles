#!/usr/bin/env bash

# Screen recording menu (SUPER + Print).
#
# Lists every script in presets/ by its `# label:` line and runs the one you
# pick. Each preset is a one-line wrapper around screen-record.sh flags
# (--area, --res, --audio), so adding an option is dropping in a new file --
# the numeric prefix sets its place in the list.
#
# While a recording is running, SUPER + Print stops it instead of opening the
# menu, like every other recording bind.
#
# The selection is resolved by ROW INDEX (-format i), never by label text, the
# same as window-switcher.sh.

DIR="$(dirname "$(readlink -f "$0")")"
THEME="$HOME/.config/rofi/themes/recording.rasi"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/screen-record.pid"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    exec "$DIR/screen-record.sh"
fi

presets=()
labels=()
for f in "$DIR"/presets/*.sh; do
    [[ -x "$f" ]] || continue
    label=$(sed -n 's/^# label:[[:space:]]*//p' "$f" | head -1)
    presets+=("$f")
    labels+=("${label:-$(basename "$f" .sh)}")
done

if [[ ${#presets[@]} -eq 0 ]]; then
    notify-send -u critical "Screen Recording" "No presets in $DIR/presets"
    exit 1
fi

idx=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -no-custom -format i -p "󰑋  Record" -theme "$THEME")

# Empty on Escape.
[[ "$idx" =~ ^[0-9]+$ ]] || exit 0

# Let rofi's surface disappear before a full-screen capture starts, or its
# last frame ends up at the start of the video.
sleep 0.2
exec "${presets[$idx]}"
