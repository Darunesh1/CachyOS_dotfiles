#!/usr/bin/env bash

# Display menu (SUPER + CTRL + D).
#
# Pick how an external monitor or TV is used: mirror the laptop screen, extend
# to the left or right, or run on one screen only.
#
# It opens with or without a cable attached. With nothing plugged in the choice
# is simply recorded, and the next display to be connected comes up in that
# mode -- see config/monitors.lua, which stores the mode on the empty-name
# catch-all rule rather than under a connector name, which is what makes that
# work.
#
# The choice persists across `hyprctl reload` and across reboots, because it is
# written to config/display-mode.lua and read back by config/monitors.lua. It
# used to live only in the compositor's memory, so the `hyprctl reload` that
# scripts/wallpaper/set-wallpaper.sh ran on every wallpaper change -- including
# the one awww-cycle.sh triggers every 200 s -- silently put it back to
# mirroring within three and a half minutes.
#
# Rules are applied with `hyprctl eval`, not `hyprctl keyword`: under the Lua
# config manager keyword refuses with "can't work with non-legacy parsers. Use
# eval." Every eval is checked -- it prints "ok", or a line starting with
# "error:", and a failure that is swallowed looks exactly like a menu that does
# nothing.
#
# Which rows are cheap, from the Hyprland 0.56.2 source: `position` and
# `mirror` are soft properties needing no modeset, so Mirror and the two
# Extends are the cheap ones; `disabled` is a hard property and always costs a
# modeset, so the two single-screen rows are inherently slower and there is
# nothing to be done about that.
#
# The source also shows mirroring calling `lockSoftwareForMonitor()` on the
# mirror source, which would force software cursors for as long as a display is
# mirrored. That is a source reading only -- it could not be confirmed on this
# machine (no such line appears in the log, and Hyprland's own logging here is
# nearly silent), so do not treat it as measured.

INTERNAL="eDP-1"
THEME="$HOME/.config/rofi/themes/powermenu.rasi"
STATE="$HOME/.config/hypr/config/display-mode.lua"

notify() { notify-send -a "Display" -i video-display-symbolic "$@"; }

# ── Current state, in one read ──────────────────────────────────────────────
#
# One `hyprctl monitors all -j` instead of the four this script used to make.
# Not where the lag was (3.8 ms each), but it removes the window in which four
# separate reads could disagree with each other.
#
# `monitors all`, not `monitors`: a display switched off by "Laptop screen
# only" is still connected and has to stay in the list, or there would be no
# way back. An unplugged one is gone from it entirely.
#
# FALLBACK is filtered out. It is the headless placeholder Hyprland 0.56
# creates when the last real monitor goes (src/state/FallbackState.hpp) so the
# session survives; it displays nothing. Counting it as an attached display
# would make this menu believe there is a screen to draw on while the machine
# is actually dark -- precisely when the rescue below has to run.
read_state() {
    local json
    json="$(hyprctl monitors all -j 2>/dev/null)" || return 1
    IFS=$'\t' read -r EXT EXT_OFF EXT_MIRROR INT_OFF <<<"$(
        jq -r --arg int "$INTERNAL" '
            (map(select(.name != $int and .name != "FALLBACK")) | .[0]) as $e
            | [ ($e.name // ""),
                (($e.disabled // false) | tostring),
                ($e.mirrorOf // ""),
                (((map(select(.name == $int and .disabled == true)) | length) > 0) | tostring) ]
            | @tsv' <<<"$json"
    )"
}

# ── Rule generation ─────────────────────────────────────────────────────────
#
# Every rule names every key. A monitor rule MERGES into the output's existing
# rule rather than replacing it -- measured: after `scale = 2`, a later rule
# omitting `scale` left it at 2 -- so an omitted key keeps whatever was there
# before. That is how "Mirror" after "Laptop screen only" used to report
# success over a screen that stayed dark, and how "Extend" after "Mirror" used
# to stay mirrored.
#
# rule <output> <position> <mirror> <disabled> [mode]
rule() {
    printf 'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = 1, mirror = "%s", disabled = %s })' \
        "$1" "${5:-preferred}" "$2" "$3" "$4"
}

internal_on="$(rule "$INTERNAL" "0x0" "" false "1920x1080@60")"
internal_off="$(rule "$INTERNAL" "0x0" "" true "1920x1080@60")"

# apply <what it is called> <lua chunk> [<lua chunk> ...] -- stops at the first
# failure. Usually called with a single chunk now; the loop is kept so a future
# action that genuinely needs two evals still fails loudly rather than halfway.
apply() {
    local label=$1 out; shift
    local lua
    for lua in "$@"; do
        out=$(hyprctl eval "$lua" 2>&1)
        if [[ "$out" == error:* ]]; then
            notify "$label failed" "${out#error: }"
            return 1
        fi
    done
    return 0
}

# save_mode <label> <position> <mirror> <disabled>
#
# Written through a temp file and renamed, because config/monitors.lua may be
# read by a `hyprctl reload` at any moment and a half-written file would be
# malformed Lua. The rename is atomic, so a reader sees the old file or the new
# one and never a partial one.
#
# Called only after `apply` succeeds, so a failed eval cannot persist a mode
# that was never actually reached.
save_mode() {
    local tmp="$STATE.new.$$"
    {
        printf -- '-- Generated by scripts/display/display-menu.sh. Do not edit; it is overwritten.\n'
        printf -- '-- Read by config/monitors.lua, which falls back to mirroring if this file is\n'
        printf -- '-- missing, empty or malformed. Delete it to go back to the default.\n'
        printf -- '--\n'
        printf -- '-- "External screen only" is deliberately NOT representable here: it stores the\n'
        printf -- '-- external geometry only, and the laptop panel being off is applied live and\n'
        printf -- '-- never written, so a reload or a reboot always comes back with a lit screen.\n'
        printf -- '--\n'
        printf -- '-- `label` is for the menu message line only; monitors.lua ignores it.\n'
        printf -- 'return {\n    label    = "%s",\n    position = "%s",\n    mirror   = "%s",\n    disabled = %s,\n}\n' \
            "$1" "$2" "$3" "$4"
    } >"$tmp" && mv -f "$tmp" "$STATE"
}

stored_label() {
    grep -oE 'label[[:space:]]*=[[:space:]]*"[^"]+"' "$STATE" 2>/dev/null \
        | head -1 | cut -d'"' -f2
}

# ── Go ──────────────────────────────────────────────────────────────────────

read_state || { notify "Display" "Could not reach Hyprland."; exit 1; }

# The one case where the menu must not open: no display attached AND the laptop
# panel switched off. There is no lit screen for rofi to draw on, so this is a
# blind keybind, and SUPER + CTRL + D is the way out.
#
# The rescue is a reload, not an eval of internal_on. Monitor rules are applied
# from a `render.preChecks` listener and `canRender()` is false while a monitor
# is disabled, so with nothing rendering the eval can be queued and never
# applied (upstream discussion #15437). A config reload is the only path that
# calls `ensureMonitorStatus()` synchronously, and since config/monitors.lua
# now names `disabled = false` for eDP-1 and reads the mode from disk, the
# reload relights the panel without discarding the chosen mode.
#
# config/monitors.lua's monitor.removed hook should get here first and make
# this unreachable. It stays because it costs nothing and works when the hook
# does not.
if [[ -z "$EXT" && "$INT_OFF" == true ]]; then
    hyprctl reload >/dev/null 2>&1
    notify "Laptop screen back on" "The external display was unplugged."
    exit 0
fi

if [[ -z "$EXT" ]]; then
    status="No display attached  ·  '$(stored_label || echo mirror)' applies when one is plugged in"
elif [[ "$INT_OFF" == true ]]; then
    status="$EXT connected  ·  external screen only"
elif [[ "$EXT_OFF" == true ]]; then
    status="$EXT connected but switched off  ·  laptop screen only"
elif [[ -n "$EXT_MIRROR" && "$EXT_MIRROR" != none ]]; then
    status="$EXT connected  ·  mirroring the laptop screen"
else
    status="$EXT connected  ·  extended"
fi

mirror_row="󰍹  Mirror -- same picture on both"
right_row="󰍺  Extend -- external on the right"
left_row="󰍺  Extend -- external on the left"
laptop_row="󰌢  Laptop screen only"
ext_row="󰟴  External screen only"

choice=$(printf '%s\n' "$mirror_row" "$right_row" "$left_row" "$laptop_row" "$ext_row" \
    | rofi -dmenu -i -no-custom -p "󰍹  Display" -mesg "$status" -theme "$THEME" \
        -theme-str 'window { width: 620px; }
                    mainbox { children: [ inputbar, message, listview ]; }
                    message { padding: 8px 14px; }
                    entry { placeholder: ""; }
                    textbox { text-color: @fg1; }')

[[ -z "$choice" ]] && exit 0

# set_mode <label> <position> <mirror> <disabled> <notify title> <notify body>
#
# Builds ONE Lua chunk and applies it in ONE eval, where this used to be two.
# Measured: one eval 9.2 ms median, two evals 18.8 ms.
#
# The eDP-1 statement is included only when the panel is actually switched off,
# because re-applying a rule that changes nothing is pointless. Note what this
# is NOT: it is not a lag fix. The theory was that re-applying eDP-1's rule
# forced a modeset of the panel every time, but counting `Modesetting eDP-1` in
# the compositor log across a Mirror -> Extend action gives **0 on both the old
# and the new script**. The rule comparison sees every hard property unchanged
# and does nothing, exactly as the cost model in the Hyprland source says it
# should. The modesets visible in the log around 10468-10596 were real
# `disabled` transitions from the single-screen rows, not stray ones.
#
# For the record, the whole script runs in ~40 ms either way (old 36.7 ms
# median, new 46.0 ms, ranges overlapping) -- so none of this was ever the lag
# anyone could feel. What is left as a candidate is compositor-side: switching
# mirror on or off migrates every workspace to another monitor with an
# animation each, rebuilds the layout, and updates the surface scale of every
# window. That is not something this script can make faster.
#
# Both the named rule for the attached output and the catch-all are emitted.
# The named rule guarantees the effect on the connector that is here right now;
# the catch-all is what gets written to disk and what the next connector will
# match. Whether a runtime eval of an empty-name catch-all re-applies to an
# already-connected output is not verified, so the named rule is not redundant.
# Both are in the same chunk, so it is still one eval and one reconfigure. The
# named rule is session-only and dies on the next reload, so it cannot shadow
# the stored catch-all later.
set_mode() {
    local label=$1 position=$2 mirror=$3 disabled=$4 title=$5 body=$6
    local chunk=""

    [[ "$INT_OFF" == true ]] && chunk="$internal_on; "
    [[ -n "$EXT" ]] && chunk+="$(rule "$EXT" "$position" "$mirror" "$disabled"); "
    chunk+="$(rule "" "$position" "$mirror" "$disabled")"

    apply "$title" "$chunk" || return 1
    save_mode "$label" "$position" "$mirror" "$disabled"
    notify "$title" "$body"
}

no_display_note() {
    [[ -z "$EXT" ]] && printf 'Saved. It applies when a display is plugged in.' \
                    || printf '%s' "$1"
}

case "$choice" in
    "$mirror_row")
        set_mode mirror auto "$INTERNAL" false "Mirroring" \
            "$(no_display_note "$EXT shows the same as the laptop screen.")"
        ;;
    "$right_row")
        set_mode extend-right auto-right "" false "Extended" \
            "$(no_display_note "$EXT is to the right of the laptop screen.")"
        ;;
    "$left_row")
        set_mode extend-left auto-left "" false "Extended" \
            "$(no_display_note "$EXT is to the left of the laptop screen.")"
        ;;
    "$laptop_row")
        # Persisted, so a display plugged in later also comes up switched off.
        # That is a change from the old behaviour, where the choice died at the
        # next reload. The panel is lit and this menu still works, so it is a
        # surprise rather than a lockout -- pick any other row to undo it.
        set_mode laptop-only auto "" true "Laptop screen only" \
            "$(no_display_note "$EXT is switched off.")"
        ;;
    "$ext_row")
        if [[ -z "$EXT" ]]; then
            notify "No external display" "Nothing to switch to. Plug in a cable first."
            exit 0
        fi
        # The only row that is applied live and never stored: what it writes is
        # the extend geometry, and `internal_off` is appended to the live chunk
        # alone. A reload or a reboot therefore always comes back with the panel
        # lit and the external extended, which is the whole reason this row
        # stopped being a one-way trip to a black screen.
        #
        # internal_off goes LAST: the mirror's source is the laptop panel, so
        # switching it off while $EXT still mirrors it would blank both.
        chunk="$(rule "$EXT" auto "" false); $(rule "" auto "" false); $internal_off"
        if apply "External screen only" "$chunk"; then
            save_mode extend-right auto-right "" false
            notify "External screen only" \
                "The laptop screen is off. Unplugging brings it back by itself; SUPER + CTRL + D also works."
        fi
        ;;
esac
