#!/usr/bin/env bash
# label: 󰍹  Full screen  720p     󰕾 system sound
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" --area full --res 720 --audio system
