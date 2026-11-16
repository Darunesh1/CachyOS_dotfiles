#!/usr/bin/env bash
#
# Prism, the workspace overview (quickshell/overview): start, show, hide or stop.
#
#   toggle.sh open        show it; does nothing if it is already open
#   toggle.sh close       hide it; does nothing if it is not open
#   toggle.sh toggle      open it, or close it if it is open (SUPER + O)
#   toggle.sh resident    start the always-ready instance, if there is room for it
#   toggle.sh stop        stop the instance entirely (Game Mode uses this)
#   toggle.sh tier        print "full" or "lite" and why
#
# TWO TIERS, because 8 GB is a hard constraint (decisions/0001-oomd-avoid-over-omit.md):
#
#   full  a RESIDENT instance runs from login, hidden, so the three-finger swipe can
#         drive it from the first millimetre. A hidden Quickshell with no window at
#         all measured 148 MiB RSS, so this is a standing cost.
#   lite  no resident instance. Started on demand and gone when closed, with a plainer
#         look (PRISM_LITE=1). Used while Game Mode is on, or when MemAvailable is below
#         LOW_KB. The swipe cannot follow its first ~200 ms in lite: that is the price.
#
# A resident instance also quits itself if memory drops below LOW_KB (a timer in
# shell.qml). It comes back only above HIGH_KB, a higher mark, so it cannot flap.
# The two figures are a first guess, not a measurement: change them with
# PRISM_LOW_KB and PRISM_HIGH_KB once there is real data.
#
# It runs as a separate process on purpose: a bug in it can close the overview but
# cannot take the session down.

set -u

CFG=overview
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
PRISM="$RUNDIR/prism"
GAME="$RUNDIR/game-mode/active"
LOW_KB="${PRISM_LOW_KB:-1000000}"
HIGH_KB="${PRISM_HIGH_KB:-1600000}"

mem_kb() { awk '/^MemAvailable:/ {print $2}' /proc/meminfo; }

instance_pid() { qs list -c "$CFG" -j 2>/dev/null | jq -r '.[0].pid // empty' 2>/dev/null; }

# The resident instance writes its pid here. A file left by a crash proves nothing,
# so the pid is checked against /proc as well.
resident_pid() {
    local p
    p=$(cat "$PRISM/pid" 2>/dev/null) || return 1
    [[ "$p" =~ ^[0-9]+$ && "$(cat "/proc/$p/comm" 2>/dev/null)" == qs ]] || return 1
    echo "$p"
}

# Prints "full" or "lite"; the reason goes to stderr for `tier`.
# $1 = the mark to compare MemAvailable against (LOW to keep, HIGH to start).
tier() {
    local mark="${1:-$LOW_KB}" kb
    if [[ -f "$GAME" ]]; then echo "Game Mode is on" >&2; echo lite; return; fi
    kb=$(mem_kb)
    if [[ -n "$kb" && "$kb" -lt "$mark" ]]; then
        echo "MemAvailable ${kb} kB is below ${mark} kB" >&2; echo lite; return
    fi
    echo "Game Mode off, MemAvailable ${kb} kB" >&2; echo full
}

# qs prints its own INFO lines ("Launching config", "Killed <id>"). Nothing reads
# them when this runs from a gesture or a keybind, so they are dropped.
# MALLOC_ARENA_MAX=1: measured on this machine, a hidden resident instance settles at
# 238 MiB RSS with glibc's default arenas and 195 MiB with one. Qt allocates from
# several threads and each thread's arena keeps what it freed.
launch_resident() {
    mkdir -p "$PRISM"
    MALLOC_ARENA_MAX=1 PRISM_RESIDENT=1 qs -c "$CFG" -d -n >/dev/null 2>&1
}
launch_ondemand() {
    local lite=0
    [[ "$(tier "$LOW_KB" 2>/dev/null)" == lite ]] && lite=1
    MALLOC_ARENA_MAX=1 PRISM_LITE=$lite qs -c "$CFG" -d -n >/dev/null 2>&1
}

# Ask a running instance to do something over IPC, with a hard time limit: `-k`
# follows SIGTERM with SIGKILL. `timeout 1` alone only sends SIGTERM, which a stopped
# or hung process never answers; measured: with the overview frozen (SIGSTOP) the
# first version of this took 31 SECONDS and left it alive.
ipc() { timeout -k 0.3 1 qs ipc -c "$CFG" call overview "$@" >/dev/null 2>&1; }

# A hung overview holding the keyboard must ALWAYS be possible to get rid of, and
# the polite routes do not work on a wedged process, so this ends in SIGKILL by pid.
# (`qs kill` is also polite and cannot kill a stopped process.)
kill_pid() {
    local pid="$1"
    kill -TERM "$pid" 2>/dev/null
    sleep 0.3
    kill -KILL "$pid" 2>/dev/null
    rm -f "$PRISM/pid"
}

# Hide it. A resident instance stays alive, so it is not waited on; an on-demand one
# quits itself, so it is. Either way, no answer means it is wedged.
hide() {
    local pid i
    pid=$(instance_pid)
    [[ -n "$pid" ]] || return 0

    if ipc conceal; then
        resident_pid >/dev/null && return 0
        for i in 1 2 3 4 5 6 7 8; do
            sleep 0.1
            kill -0 "$pid" 2>/dev/null || return 0
        done
    fi
    kill_pid "$pid"
}

# Show it. A resident instance that has only just been started may not be listening
# yet, so ask for a little while rather than once.
show() {
    local i
    if [[ -z "$(instance_pid)" ]]; then
        launch_ondemand
        return 0
    fi
    for i in 1 2 3 4 5 6 7 8 9 10; do
        ipc reveal && return 0
        sleep 0.1
    done
}

stop() {
    local pid
    pid=$(instance_pid)
    [[ -n "$pid" ]] || { rm -f "$PRISM/pid"; return 0; }
    ipc quit
    for _ in 1 2 3 4 5; do
        sleep 0.1
        kill -0 "$pid" 2>/dev/null || { rm -f "$PRISM/pid"; return 0; }
    done
    kill_pid "$pid"
}

case "${1:-toggle}" in
    open)     show ;;
    close)    hide ;;
    toggle)   if [[ -n "$(instance_pid)" ]]; then ipc toggleShow || hide; else launch_ondemand; fi ;;
    resident)
        # Only when there is room for it, and when nothing is running already.
        [[ -z "$(instance_pid)" && "$(tier "$HIGH_KB" 2>/dev/null)" == full ]] && launch_resident
        ;;
    stop)     stop ;;
    tier)     tier "$LOW_KB" ;;
    *)        echo "usage: ${0##*/} [open|close|toggle|resident|stop|tier]" >&2; exit 2 ;;
esac
exit 0
