#!/usr/bin/env bash
# label: 󰍹  Full screen  native   󰖁 no sound
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" --area full --res native --audio none
