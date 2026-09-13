#!/usr/bin/env bash
# label: 󰍹  Full screen  720p     󰖁 no sound
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" --area full --res 720 --audio none
