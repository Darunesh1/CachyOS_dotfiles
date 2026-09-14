#!/usr/bin/env bash

# Waybar custom/network: ONE Wi-Fi symbol that also tells you whether the
# internet actually works.
#
# waybar's built-in network module only knows whether the link is up, so it
# showed "󰤨 81%" on a Wi-Fi with no internet. This module combines the link
# with NetworkManager's connectivity check
# (/usr/lib/NetworkManager/conf.d/20-connectivity.conf):
#
#   internet works          󰤟 󰤢 󰤥 󰤨 + signal %      class full
#   connected, no internet  󰤫  (Wi-Fi with "!")       class limited
#   login page in the way   󰤬  (Wi-Fi with a lock)    class portal
#   not connected           󰤮                         class disconnected
#   connecting              󰤯                         class connecting
#   Wi-Fi radio off         󰖪                         class off
#   ethernet                󰈀  (+ the classes above)
#
# Built to cost next to nothing, since this machine is for gaming on 8 GB:
#   * Link state and connectivity rarely change, so they are read with nmcli
#     only when `nmcli monitor` reports an event (or one of our checks ends).
#   * Every TICK seconds only the signal (/proc/net/wireless) and the byte
#     counters (/sys) are read -- with bash builtins, no process is started.
#   * NetworkManager only re-tests the internet every 5 minutes once it has
#     seen it working, so a phone hotspot whose mobile data is switched off
#     went unnoticed for minutes. While a link is up we ask NM to re-check
#     every CHECK_EVERY seconds and right after connecting -- in the
#     background, never more than one at a time, no sudo needed.
#   * Game Mode (hypr/scripts/power/game-mode.sh) SIGSTOPs this script; the
#     bar keeps the last icon, and it catches up as soon as it is resumed.
#
#   network-status.sh            stream JSON for waybar
#   network-status.sh --click    login page if behind a portal, else Wi-Fi settings
#   network-status.sh --recheck  make NetworkManager re-check the internet now

TICK=3
CHECK_EVERY=30
LAST_FILE="${XDG_RUNTIME_DIR:-/tmp}/network-status.last"
PORTAL_URL="http://neverssl.com"

connectivity() { nmcli -t -f CONNECTIVITY general 2>/dev/null; }

case "${1:-}" in
    --click)
        if [[ "$(connectivity)" == "portal" ]]; then
            setsid -f xdg-open "$PORTAL_URL" >/dev/null 2>&1
        else
            setsid -f nm-connection-editor >/dev/null 2>&1
        fi
        exit 0
        ;;
    --recheck)
        # The monitor loop below picks the result up as an event.
        nmcli networking connectivity check >/dev/null 2>&1
        exit 0
        ;;
esac

# ── Cached link state: refreshed on NetworkManager events only ───────────────
iface="" kind="" devstate="" conn="" ssid="" freq=""

refresh_state() {
    local dev type dstate name line f
    iface="" kind="" devstate="" ssid="" freq=""

    # A connected ethernet wins, else the Wi-Fi device.
    while IFS=: read -r dev type dstate name; do
        case "$type" in
            ethernet) [[ "$dstate" == connected ]] && { iface=$dev; kind=ethernet; devstate=$dstate; ssid=$name; break; } ;;
            wifi)     [[ -z "$kind" ]] && { iface=$dev; kind=wifi; devstate=$dstate; ssid=$name; } ;;
        esac
    done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null)

    conn="$(connectivity)"

    # SSID and frequency (--rescan no never triggers a scan).
    if [[ "$kind" == wifi && "$devstate" == connected ]]; then
        line=$(nmcli -t -f IN-USE,FREQ,SSID dev wifi list --rescan no ifname "$iface" 2>/dev/null | grep -m1 '^\*')
        if [[ -n "$line" ]]; then
            IFS=: read -r _ f _ <<<"$line"
            freq=${f% MHz}
            ssid=${line#*:*:}
            ssid=${ssid//\\:/:}
        fi
    fi
}

# ── Per-tick reads: builtins only ────────────────────────────────────────────

# Signal % from the live link level, using NetworkManager's own formula:
# clamp to -100..-40 dBm, then 100 - |dBm + 40| * 100 / 60.
sig=""
read_signal() {
    local name status link level _rest
    sig=""
    [[ "$kind" == wifi ]] || return
    while read -r name status link level _rest; do
        [[ "$name" == "$iface:" ]] || continue
        level=${level%%.*}
        if (( level < 0 )); then
            (( level < -100 )) && level=-100
            (( level > -40 ))  && level=-40
            sig=$(( 100 - (-40 - level) * 100 / 60 ))
        else
            link=${link%%.*}                # driver reports quality, not dBm
            sig=$(( link * 100 / 70 ))
        fi
        return
    done < /proc/net/wireless
}

# "1536" -> "1.5 MB/s" into the named variable, in plain integer bash.
human_rate() {
    local -n _out=$1
    local b=$2
    if   (( b >= 1048576 )); then printf -v _out '%d.%d MB/s' $((b / 1048576)) $((b % 1048576 * 10 / 1048576))
    elif (( b >= 1024 ));    then printf -v _out '%d KB/s' $((b / 1024))
    else                          printf -v _out '%d B/s' "$b"
    fi
}

prev_rx=0 prev_tx=0 prev_t=0 prev_if="" rate=""
read_rate() {
    local rx tx now dt down up
    rate=""
    [[ -n "$iface" && -r /sys/class/net/$iface/statistics/rx_bytes ]] || return
    read -r rx < "/sys/class/net/$iface/statistics/rx_bytes"
    read -r tx < "/sys/class/net/$iface/statistics/tx_bytes"
    now=${EPOCHREALTIME/./}
    if [[ "$iface" == "$prev_if" ]] && (( prev_t > 0 )); then
        dt=$(( (now - prev_t) / 1000 ))  # ms
        if (( dt > 0 )); then
            human_rate down $(( (rx - prev_rx) * 1000 / dt ))
            human_rate up   $(( (tx - prev_tx) * 1000 / dt ))
            rate="↓ $down  ↑ $up"
        fi
    fi
    prev_rx=$rx prev_tx=$tx prev_t=$now prev_if=$iface
}

# ── Internet re-checks ───────────────────────────────────────────────────────
# With no internet a check waits for its HTTP timeout, so never stack a second
# one on a check that is still running.
check_pid=0 last_check=0
request_check() {
    (( check_pid > 0 )) && kill -0 "$check_pid" 2>/dev/null && return
    nmcli networking connectivity check >/dev/null 2>&1 &
    check_pid=$!
    last_check=$EPOCHSECONDS
}

# ── Output ───────────────────────────────────────────────────────────────────
prev_state=""
[[ -r "$LAST_FILE" ]] && read -r prev_state < "$LAST_FILE"
last_json=""

emit() {
    local state text tooltip icon esc json

    if [[ -z "$kind" || "$devstate" == unavailable || "$devstate" == unmanaged ]]; then
        state=off
    elif [[ "$devstate" == connecting* ]]; then
        state=connecting
    elif [[ "$devstate" != connected ]]; then
        state=disconnected
    else
        case "$conn" in
            limited) state=limited ;;
            portal)  state=portal ;;
            *)       state=full ;;   # full, or not checked yet: trust the link
        esac
    fi

    case "$state" in
        full)
            if [[ "$kind" == ethernet ]]; then
                text="󰈀"
            else
                if   (( ${sig:-0} >= 75 )); then icon="󰤨"
                elif (( ${sig:-0} >= 50 )); then icon="󰤥"
                elif (( ${sig:-0} >= 25 )); then icon="󰤢"
                else                             icon="󰤟"; fi
                text="$icon ${sig:-0}%"
            fi
            tooltip="Connected · internet OK"
            ;;
        limited)
            if [[ "$kind" == ethernet ]]; then text="󰈀"; else text="󰤫"; fi
            tooltip="Connected, but NO INTERNET\nRight-click to re-check"
            ;;
        portal)       text="󰤬"; tooltip="Login page required\nClick to open it" ;;
        connecting)   text="󰤯"; tooltip="Connecting…" ;;
        disconnected) text="󰤮"; tooltip="Not connected\nClick for Wi-Fi settings" ;;
        off)          text="󰖪"; tooltip="Wi-Fi is off" ;;
    esac

    if [[ "$devstate" == connected && -n "$ssid" ]]; then
        esc=${ssid//\\/\\\\}
        esc=${esc//\"/\\\"}
        [[ -n "$sig" ]]  && esc+="  ·  ${sig}%"
        [[ -n "$freq" ]] && esc+="  ·  $((freq / 1000)).$((freq % 1000 / 100)) GHz"
        tooltip="$esc\n$tooltip"
    fi
    [[ "$devstate" == connected && -n "$rate" ]] && tooltip+="\n$rate"

    # Notify on internet changes only, never repeatedly.
    if [[ "$state" != "$prev_state" ]]; then
        printf '%s\n' "$state" > "$LAST_FILE"
        case "$state" in
            limited) notify-send -u critical "Wi-Fi" "Connected, but no internet" ;;
            portal)  notify-send "Wi-Fi" "Login required -- click the Wi-Fi icon" ;;
            full)    [[ "$prev_state" == limited || "$prev_state" == portal ]] && notify-send "Wi-Fi" "Internet is back" ;;
        esac
        prev_state=$state
    fi

    printf -v json '{"text":"%s","class":"%s","tooltip":"%s"}' "$text" "$state" "$tooltip"
    if [[ "$json" != "$last_json" ]]; then
        printf '%s\n' "$json"
        last_json=$json
    fi
}

# ── Main loop ────────────────────────────────────────────────────────────────
refresh_state
[[ "$devstate" == connected ]] && request_check
read_signal
emit

exec 3< <(nmcli monitor 2>/dev/null)
monitor_pid=$!

# When waybar restarts, our next write hits a closed pipe (SIGPIPE). Take the
# children down with us, or they linger. check_pid is guarded: `kill 0` would
# signal the whole process group, waybar included.
cleanup() {
    kill "$monitor_pid" 2>/dev/null
    (( check_pid > 0 )) && kill "$check_pid" 2>/dev/null
}
trap 'cleanup; exit 0' PIPE TERM INT HUP
trap cleanup EXIT

while true; do
    was=$devstate
    read -r -t "$TICK" -u 3 _
    rc=$?
    if (( rc == 0 )); then
        # Events come in bursts (a connect is several lines): settle, then refresh once.
        while read -r -t 0.2 -u 3 _; do :; done
        refresh_state
    elif (( rc == 1 )); then
        # EOF: NetworkManager went away. waybar's restart-interval brings us
        # back, rather than spinning on a dead pipe.
        exit 1
    fi

    # One of our checks finished. A change would also arrive as an event, but
    # read the result once to be sure -- connectivity only: a check cannot
    # change the link itself, so the full refresh would be wasted work.
    if (( check_pid > 0 )) && ! kill -0 "$check_pid" 2>/dev/null; then
        check_pid=0
        conn="$(connectivity)"
    fi

    # Re-test straight after (re)connecting, then every CHECK_EVERY seconds.
    if [[ "$devstate" == connected ]]; then
        if [[ "$was" != connected ]] || (( EPOCHSECONDS - last_check >= CHECK_EVERY )); then
            request_check
        fi
    fi

    read_signal
    read_rate
    emit
done
