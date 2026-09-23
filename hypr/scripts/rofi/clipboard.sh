#!/usr/bin/env bash

# Clipboard history picker (SUPER + V), backed by cliphist.
#
# Ctrl+Shift+Delete wipes the whole history (after a confirmation prompt).
#
# Two things the old inline `cliphist list | rofi | cliphist decode` pipeline
# got wrong, both of which broke searching:
#
#   1. cliphist prefixes every row with its numeric id and a tab. Those digits
#      are part of the string rofi matches against, so typing any number lit up
#      every row in the list. The id is now stripped from what is displayed and
#      the selection is resolved by ROW INDEX (-format i), never by the text.
#   2. cliphist escapes non-ASCII in its preview as literal \u{2601} sequences.
#      Searching for the character you actually copied could not match the
#      escape, so those rows were unreachable. They are unescaped for display.
#
# Decoding still goes through the id, so the mangled preview never has to be
# parsed back into an entry.

THEME="$HOME/.config/rofi/themes/clipboard.rasi"

if ! command -v cliphist >/dev/null 2>&1; then
    notify-send -u critical -a "Clipboard" -i edit-paste-symbolic "Clipboard" "cliphist is not installed. Run: sudo pacman -S cliphist"
    exit 1
fi

mapfile -t rows < <(cliphist list 2>/dev/null)

if [[ ${#rows[@]} -eq 0 ]]; then
    notify-send -a "Clipboard" -i edit-paste-symbolic "Clipboard" "History is empty"
    exit 0
fi

# ids[] and labels[] stay index-aligned with what rofi is shown.
ids=()
labels=()
for row in "${rows[@]}"; do
    ids+=("${row%%$'\t'*}")
    labels+=("${row#*$'\t'}")
done

# \u{XXXX} -> the character itself, so search matches what was copied.
unescape() {
    perl -CS -pe 's/\\u\{([0-9a-fA-F]+)\}/chr(hex($1))/ge' 2>/dev/null || cat
}

wipe() {
    local answer
    answer=$(printf 'No, keep it\nYes, clear everything\n' | rofi -dmenu -i \
        -p "󰅍  Clipboard" -mesg "Clear all ${#rows[@]} clipboard entries?" \
        -theme "$THEME")
    if [[ "$answer" == "Yes,"* ]]; then
        cliphist wipe && notify-send -a "Clipboard" -i edit-paste-symbolic "Clipboard" "History cleared"
    fi
}

idx=$(printf '%s\n' "${labels[@]}" | unescape | rofi -dmenu -i -matching fuzzy \
        -format i -p "󰅍  Clipboard" \
        -mesg "Ctrl+Shift+Del  clear history" \
        -kb-custom-1 "Control+Shift+Delete" \
        -theme "$THEME")
status=$?

# 10 is rofi's exit code for -kb-custom-1.
if [[ $status -eq 10 ]]; then
    wipe
    exit 0
fi

# Empty on Escape; non-numeric if rofi hands back unmatched custom input.
[[ "$idx" =~ ^[0-9]+$ ]] || exit 0

# Argument form, not a here-string: cliphist rejects the trailing newline
# a here-string appends ("parsing \"174\\n\": invalid syntax").
cliphist decode "${ids[$idx]}" | wl-copy
