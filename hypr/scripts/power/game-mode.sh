#!/usr/bin/env bash

# Game Mode -- reached from the power-profile menu (SUPER + SHIFT + G).
#
#   game-mode.sh [toggle|on|off|status]      default: toggle
#
# Built on what CachyOS already ships rather than on Feral gamemode, which the
# CachyOS wiki says fights ananicy-cpp over process niceness:
#
#   * power-profiles-daemon -> performance. CachyOS patches ppd so that this
#     also switches the running sched-ext scheduler (scx_lavd, started at boot
#     by scx_loader -- install.sh stage 8) into its Gaming mode, and back to
#     Auto when the profile returns. On Intel it raises EPP; the governor
#     stays "powersave", which is expected.
#   * ananicy-cpp keeps running and keeps boosting known game processes.
#
# On top of that, for the desktop itself:
#   * animations, blur and shadows off; VFR off
#   * render:direct_scanout = 2: fullscreen games skip compositing entirely,
#     which matters on an iGPU the desktop and the game share
#   * swaync Do Not Disturb on
#   * the wallpaper cycle frozen (SIGSTOP), so no wallust run + hyprctl reload
#     lands in the middle of a game every 200 s
#   * the waybar network module frozen too: zero CPU while gaming. The bar
#     keeps its last icon; internet re-checks resume when Game Mode ends.
#
# Everything that is changed is saved first and restored exactly on "off" --
# including whichever power profile was active before, not always balanced.

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/game-mode"
SCRIPTS="$(dirname "$(readlink -f "$0")")"
# Anchored on the interpreter: an unanchored `pkill -f awww-cycle.sh` would
# also SIGSTOP anything that merely mentions the path, like an editor with the
# script open or a shell whose command line contains it.
CYCLE_PATTERN='^(/usr)?/bin/bash [^ ]*/wallpaper/awww-cycle\.sh$'
# waybar starts its custom scripts as plain `bash <path>`. The trailing $ keeps
# the --click / --recheck runs of the same script from ever being matched.
NETWORK_PATTERN='^([^ ]*/)?bash [^ ]*/waybar/scripts/network-status\.sh$'

have() { command -v "$1" >/dev/null 2>&1; }
notify() { have notify-send && notify-send "Game Mode" "$1"; }
save() { printf '%s\n' "$2" > "$STATE_DIR/$1"; }
saved() { cat "$STATE_DIR/$1" 2>/dev/null; }
is_on() { [[ -f "$STATE_DIR/active" ]]; }

enable() {
    is_on && return 0
    mkdir -p "$STATE_DIR"

    # ── Power profile (+ scx Gaming mode via CachyOS's ppd patch) ───────────
    if have powerprofilesctl; then
        save profile "$(powerprofilesctl get)"
        powerprofilesctl set performance
    fi

    # ── Compositor ──────────────────────────────────────────────────────────
    save scanout "$(hyprctl getoption render:direct_scanout 2>/dev/null | awk '/^int:/ {print $2}')"
    hyprctl eval 'hl.config({
        animations = { enabled = false },
        decoration = {
            shadow = { enabled = false },
            blur   = { enabled = false },
        },
        debug  = { vfr = false },
        render = { direct_scanout = 2 },
    })' >/dev/null

    # ── Notifications ───────────────────────────────────────────────────────
    if have swaync-client; then
        save dnd "$(swaync-client -D 2>/dev/null)"
        swaync-client -dn >/dev/null
    fi

    # ── Background work ─────────────────────────────────────────────────────
    # SIGSTOP the loop itself: its current `sleep` child finishes, and then
    # the loop simply does not continue until SIGCONT.
    pkill -STOP -f "$CYCLE_PATTERN"
    pkill -STOP -f "$NETWORK_PATTERN"

    touch "$STATE_DIR/active"

    local sched=""
    have scxctl && sched=$(scxctl get 2>/dev/null)
    if [[ -z "$sched" || "$sched" == *"no scx scheduler"* ]]; then
        notify "Enabled 🎮 -- gaming scheduler not running (run ./install.sh, stage 8)"
    else
        notify "Enabled 🎮  ($sched)"
    fi
}

disable() {
    is_on || return 0

    pkill -CONT -f "$CYCLE_PATTERN"
    pkill -CONT -f "$NETWORK_PATTERN"

    if have swaync-client && [[ "$(saved dnd)" == "false" ]]; then
        swaync-client -df >/dev/null
    fi

    # hypr-profile.sh sets both the profile and the matching desktop effects,
    # so restoring through it brings blur/shadows/VFR back correctly -- or keeps
    # them off, if the previous profile was power-saver.
    local prev
    prev="$(saved profile)"
    case "$prev" in
        power-saver) "$SCRIPTS/hypr-profile.sh" power >/dev/null ;;
        performance) "$SCRIPTS/hypr-profile.sh" performance >/dev/null ;;
        *)           "$SCRIPTS/hypr-profile.sh" balanced >/dev/null ;;
    esac

    local scanout
    scanout="$(saved scanout)"
    hyprctl eval "hl.config({ render = { direct_scanout = ${scanout:-0} } })" >/dev/null

    rm -rf "$STATE_DIR"
    notify "Disabled"
}

case "${1:-toggle}" in
    on)     enable ;;
    off)    disable ;;
    toggle) if is_on; then disable; else enable; fi ;;
    status) if is_on; then echo on; else echo off; fi; exit 0 ;;
    *)      echo "Usage: $0 [toggle|on|off|status]" >&2; exit 1 ;;
esac

# Refresh the waybar power-profile module (it shows 🎮 while active).
pkill -SIGRTMIN+9 waybar
