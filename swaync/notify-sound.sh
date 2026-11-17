#!/bin/sh
#
# Play a notification sound. Called by the `scripts` entries in config.json.
#
#   notify-sound.sh <sound> [always]
#
# <sound> is a file name without extension from the freedesktop sound theme,
# /usr/share/sounds/freedesktop/stereo/<sound>.oga. A full path is used, not a theme
# name, so a missing theme cannot turn this into a silent failure.
#
# swaync does not play sounds itself, and it runs its `scripts` even while Do Not
# Disturb is on (measured: a normal notification with DND on still ran the script).
# Game Mode turns DND on, so without this check a game would be beeped at by
# notifications whose popups are hidden. The sound follows the popup: silent under
# DND, unless `always` is given, which the critical entry does because swaync still
# shows critical notifications under DND.

[ "${2:-}" = always ] || [ "$(swaync-client -D 2>/dev/null)" != true ] || exit 0
exec pw-play "/usr/share/sounds/freedesktop/stereo/$1.oga"
