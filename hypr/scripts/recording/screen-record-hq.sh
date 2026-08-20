#!/usr/bin/env bash

# High-quality variant of screen-record.sh: constant-quality H.264 (crf 14)
# with lossless FLAC audio in an mkv container, instead of the standard
# 5 Mb/s mp4. See screen-record.sh for the full profile notes.

exec "$(dirname "$(readlink -f "$0")")/screen-record.sh" hq "$@"
