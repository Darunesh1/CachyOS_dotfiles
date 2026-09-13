#!/usr/bin/env bash
# label: 󰩭  Region       native   󰖁 no sound
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" --area region --res native --audio none
