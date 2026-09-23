#!/usr/bin/env bash

# Fuzzy file finder (SUPER + SHIFT + E).
#
# fd rather than find or plocate: its defaults already skip hidden files and
# honour .gitignore, and that is what keeps this usable. Measured on this home
# directory it is the difference between 369k paths and 23k -- rofi copes with
# the latter and crawls on the former. ~/.local alone is 11 GB of caches.
#
# The selection is resolved by ROW INDEX (-format i), never by the displayed
# text, so the leading filetype glyph never has to be parsed back off and paths
# containing spaces cannot be mangled.

THEME="$HOME/.config/rofi/themes/finder.rasi"

if ! command -v fd >/dev/null 2>&1; then
    notify-send -u critical -a "File finder" -i system-search-symbolic "File finder" "fd is not installed. Run: sudo pacman -S fd"
    exit 1
fi

cd "$HOME" || exit 1

# --strip-cwd-prefix keeps rows readable: paths show relative to $HOME.
mapfile -t files < <(
    fd --type f --strip-cwd-prefix \
       --exclude node_modules --exclude target --exclude .git 2>/dev/null
)

if [[ ${#files[@]} -eq 0 ]]; then
    notify-send -a "File finder" -i system-search-symbolic "File finder" "No files found"
    exit 0
fi

# Prepend a filetype glyph. Display only -- the index is what gets acted on.
idx=$(printf '%s\n' "${files[@]}" | awk '
    {
        n = split($0, parts, ".")
        ext = (n > 1) ? tolower(parts[n]) : ""
        if      (ext == "lua")                                      g = "󰢱"
        else if (ext ~ /^(md|markdown|rst|txt)$/)                   g = "󰍔"
        else if (ext ~ /^(sh|bash|zsh|fish)$/)                      g = "󰆍"
        else if (ext ~ /^(conf|toml|ini|rasi|json|jsonc|yaml|yml|cfg)$/) g = "󰒓"
        else if (ext ~ /^(png|jpg|jpeg|gif|svg|webp|bmp)$/)         g = "󰋩"
        else if (ext == "pdf")                                      g = "󰈦"
        else if (ext ~ /^(mp4|mkv|webm|mov|avi)$/)                  g = "󰕧"
        else if (ext ~ /^(mp3|flac|wav|opus|ogg|m4a)$/)             g = "󰝙"
        else if (ext ~ /^(zip|tar|gz|xz|bz2|7z|zst|rar)$/)          g = "󰗄"
        else if (ext == "py")                                       g = "󰌠"
        else if (ext ~ /^(js|ts|jsx|tsx|mjs|cjs)$/)                 g = "󰌞"
        else if (ext ~ /^(c|h|cpp|hpp|rs|go|java|cs)$/)             g = "󰅩"
        else                                                        g = "󰈔"
        printf "%s  %s\n", g, $0
    }
' | rofi -dmenu -i -matching fuzzy -format i \
         -p "󰍉  Find File" -theme "$THEME")

# Empty on Escape; non-numeric if rofi hands back unmatched custom input.
[[ "$idx" =~ ^[0-9]+$ ]] || exit 0

xdg-open "$HOME/${files[$idx]}" >/dev/null 2>&1 &
