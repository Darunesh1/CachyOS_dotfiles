#!/usr/bin/env bash

# Keybind cheat sheet (SUPER + /).
#
# Parsed from the Lua config on every open, so it can never go stale: add a
# bind, press SUPER + / and it is there -- no reload, no list to maintain.
#
# Why not `hyprctl binds -j`? Under the Lua config every bind reports
# `"dispatcher": "__lua"` with an opaque handle as its argument, so the live
# list knows the keys but not what any of them do.
#
# Each row is  KEY  description  section.  The description is, in order:
#   1. a comment directly above the bind -- a single line, or the first line of
#      a block when that line is a complete sentence (ends in a period);
#   2. a trailing comment on the bind line, if it starts with a capital;
#   3. otherwise derived from the action (script name, command, dispatcher).
# So the way to label a bind here is a one-line `-- Comment` above it.
#
#   keybinds.sh          open the rofi menu
#   keybinds.sh --list   print the rows to stdout instead

HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
THEME="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes/keybinds.rasi"

mainmod=$(sed -nE 's/^[[:space:]]*M\.mainMod[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$HYPR_DIR/config/lib.lua" 2>/dev/null)

list_binds() {
    MAINMOD="${mainmod:-SUPER}" awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function cap(s)  { return toupper(substr(s, 1, 1)) substr(s, 2) }
    function clip(s, n) { return length(s) > n ? substr(s, 1, n - 1) "…" : s }

    # "power-menu.sh" -> "Power menu"
    function humanise_path(p,   n, parts) {
        n = split(p, parts, "/"); p = parts[n]
        sub(/\.sh$/, "", p); gsub(/[-_]/, " ", p)
        return cap(p)
    }

    # "({ workspace = 1 }), { x })" -> "{ workspace = 1 }": the text inside
    # the first balanced pair of parens, i.e. the dispatcher arguments only.
    function first_group(s,   i, ch, depth, out) {
        if (substr(s, 1, 1) != "(") return ""
        depth = 0; out = ""
        for (i = 1; i <= length(s); i++) {
            ch = substr(s, i, 1)
            if (ch == "(") { if (depth++ == 0) continue }
            else if (ch == ")") { if (--depth == 0) return out }
            out = out ch
        }
        return out
    }

    function friendly_key(k) {
        gsub(/mainMod[ \t]*\.\.[ \t]*/, "", k)
        gsub(/"/, "", k)
        if (k ~ /^ \+ /) k = ENVIRON["MAINMOD"] k
        k = trim(k)
        sub(/mouse:272$/, "LMB drag", k)
        sub(/mouse:273$/, "RMB drag", k)
        sub(/mouse_down$/, "scroll down", k)
        sub(/mouse_up$/, "scroll up", k)
        sub(/switch:on:Lid Switch/, "Lid closed", k)
        sub(/period$/, ".", k)
        sub(/slash$/, "/", k)
        sub(/^XF86/, "", k)
        return k
    }

    function describe_action(a,   inner, q, path, args) {
        if (a ~ /function[ \t]*\(/) return "Custom action"
        if (a ~ /exec_cmd\(/) {
            inner = a; sub(/.*exec_cmd\([ \t]*/, "", inner)
            if (inner ~ /^L\.terminal/)    return "Terminal"
            if (inner ~ /^L\.fileManager/) return "File manager"
            if (inner ~ /^L\.menu/)        return "App launcher"
            if (inner ~ /^L\.[A-Za-z]+[ \t]*\.\.[ \t]*"/) {
                q = inner; sub(/^[^"]*"/, "", q); sub(/".*/, "", q)
                return humanise_path(q)
            }
            if (inner ~ /^"/) {
                q = inner; sub(/^"/, "", q); sub(/"[^"]*$/, "", q)
                return "Run: " clip(q, 48)
            }
            if (inner ~ /^\[\[/) {
                q = inner; sub(/^\[\[/, "", q); sub(/\]\].*/, "", q)
                return "Run: " clip(q, 48)
            }
            return "Run command"
        }
        if (match(a, /hl\.dsp\.[A-Za-z_.]+/)) {
            path = substr(a, RSTART + 7, RLENGTH - 7)
            gsub(/[._]/, " ", path)
            args = first_group(substr(a, RSTART + RLENGTH))
            gsub(/[{}"]/, "", args); gsub(/[ \t]*=[ \t]*/, " ", args)
            args = trim(args)
            sub(/^direction /, "", args)
            return cap(path) (args != "" ? " → " args : "")
        }
        return "Custom action"
    }

    FNR == 1 { section = ""; nc = 0 }

    # Section header:  -- ── Name ──────
    /^[ \t]*--[ \t]*──/ {
        s = $0
        sub(/^[ \t]*--[ \t]*─+[ \t]*/, "", s); sub(/[ \t]*─+[ \t]*$/, "", s)
        section = s; nc = 0; next
    }

    # Comment line: remember the block so the next bind can use it.
    /^[ \t]*--/ {
        c = $0; sub(/^[ \t]*--[ \t]?/, "", c)
        if (c ~ /^[═─]/) { nc = 0; next }
        comments[++nc] = trim(c); next
    }

    /^[ \t]*hl\.bind\(/ {
        line = $0; sub(/^[ \t]*hl\.bind\([ \t]*/, "", line)
        comma = index(line, ",")
        key = friendly_key(substr(line, 1, comma - 1))
        action = substr(line, comma + 1)

        # Trailing comment: only after a closing paren, so the "--flags"
        # inside command strings are not mistaken for one.
        trailing = ""
        if (match(action, /\)[ \t]+--[ \t]/)) {
            trailing = trim(substr(action, RSTART + RLENGTH))
            action = substr(action, 1, RSTART)
        }

        desc = ""
        if (nc == 1 || (nc > 1 && comments[1] ~ /\.$/)) {
            desc = comments[1]
            sub(/[ \t]*\(.*\)[ \t]*$/, "", desc)
            sub(/\.$/, "", desc)
            gsub(/mainMod/, ENVIRON["MAINMOD"], desc)
        }
        if (desc == "" && trailing ~ /^[A-Z]/) { desc = trailing; trailing = "" }
        if (desc == "") desc = describe_action(action)
        if (trailing != "") desc = desc " (" trailing ")"

        printf "%-26s %-50s %s\n", key, clip(desc, 50), section
        nc = 0; next
    }

    { nc = 0 }
    ' "$HYPR_DIR"/config/*.lua
}

if [[ "${1:-}" == "--list" ]]; then
    list_binds
    exit 0
fi

# Display only: picking a row just closes the menu.
list_binds | rofi -dmenu -i -no-custom -p "  Keybinds" -theme "$THEME" >/dev/null
