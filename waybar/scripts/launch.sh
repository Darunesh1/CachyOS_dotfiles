#!/bin/bash

# Restart Waybar. SIGTERM rather than `killall -9`, so it removes its layer
# surface and reaps its child scripts instead of leaving them orphaned.
pkill -x waybar
setsid waybar >/dev/null 2>&1 </dev/null &
