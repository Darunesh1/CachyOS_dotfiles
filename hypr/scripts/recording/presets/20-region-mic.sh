#!/usr/bin/env bash
# label: 󰩭  Region       native   󰍬 microphone
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" --area region --res native --audio mic
