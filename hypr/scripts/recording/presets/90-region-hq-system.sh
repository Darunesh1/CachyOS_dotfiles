#!/usr/bin/env bash
# label: 󰩭  Region HQ    native   󰕾 system sound  (crf 14, mkv)
exec "$(dirname "$(readlink -f "$0")")/../screen-record.sh" hq --area region --res native --audio system
