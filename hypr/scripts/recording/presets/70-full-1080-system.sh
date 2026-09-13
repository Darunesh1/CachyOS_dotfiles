#!/usr/bin/env bash
# label: 󰍹  Full screen  1080p    󰕾 system sound
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" --area full --res 1080 --audio system
