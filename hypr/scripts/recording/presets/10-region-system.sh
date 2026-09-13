#!/usr/bin/env bash
# label: 󰩭  Region       native   󰕾 system sound
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" --area region --res native --audio system
