#!/usr/bin/env bash
#
# Relight the screen if a resume left no lit output. Called from
# hypr/hypridle.conf's after_sleep_cmd.
#
# WHY: config/monitors.lua has a good panel rescue (rescue_panel, with a
# three-strike guard against reload loops), but it is only registered on
# `monitor.removed` and `config.reloaded`. A wake from suspend fires neither,
# so a resume that comes back dark has nothing to recover it. Hyprland exposes
# no resume event to Lua, so the trigger has to come from the one path that
# does run on resume -- hypridle's after_sleep_cmd.
#
# This asks exactly the question lit_screens() asks in monitors.lua: `hyprctl
# monitors -j` lists only ENABLED, NON-MIRRORING outputs, so its length is the
# number of screens showing a picture. FALLBACK is excluded by name for the
# same reason as there: it is the headless placeholder Hyprland creates when
# the last real output goes, and counting it would mean believing there is
# something to look at.
#
# NOTE this cannot fix a black screen whose output is still enabled -- if
# Hyprland thinks eDP-1 is lit and it is not, the count is 1 and this exits.
# That case is what the persistent logs are for.

set -u

LOG=${XDG_STATE_HOME:-$HOME/.local/state}/hypr/panel-rescue.log

log() { printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG" 2>/dev/null || true; }

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

command -v hyprctl >/dev/null || exit 0

# jq is used rather than parsed by hand because monitors -j is real JSON; it is
# already a dependency of lid-close.sh and display-menu.sh.
if ! command -v jq >/dev/null; then
    log "jq missing, cannot count outputs"
    exit 0
fi

lit=$(hyprctl monitors -j 2>/dev/null \
    | jq '[.[] | select(.name != "FALLBACK")] | length' 2>/dev/null)

# Unreadable answer is not a dark screen. Do nothing rather than reload blind.
case "$lit" in
    ''|*[!0-9]*) log "could not read output count (got '${lit}'), doing nothing"; exit 0 ;;
esac

if (( lit > 0 )); then
    exit 0
fi

log "no lit output after resume; reloading"
hyprctl reload >>"$LOG" 2>&1 || log "hyprctl reload failed rc=$?"
