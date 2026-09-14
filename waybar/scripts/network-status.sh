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
# Reacts instantly to NetworkManager events (`nmcli monitor`), and re-reads at
# least every TICK seconds for the signal % and the speed shown in the tooltip.
# How fast a drop *during* a session is noticed is NM's check interval
# (packages/NetworkManager/30-connectivity-interval.conf -> 60 s).
#
#   network-status.sh            stream JSON for waybar
#   network-status.sh --click    login page if behind a portal, else Wi-Fi settings
#   network-status.sh --recheck  make NetworkManager re-check the internet now

TICK=3
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

# "1536" -> "1.5 MB/s", in plain integer bash.
human_rate() {
    local b=$1
    if   (( b >= 1048576 )); then printf '%d.%d MB/s' $((b / 1048576)) $((b % 1048576 * 10 / 1048576))
    elif (( b >= 1024 ));    then printf '%d KB/s' $((b / 1024))
    else                          printf '%d B/s' "$b"
    fi
}

json_escape() { local s=${1//\\/\\\\}; printf '%s' "${s//\"/\\\"}"; }

# Enlarge just the glyph (Pango markup; waybar renders it in custom modules),
# leaving the "80%" beside it at the bar's normal size. Warning glyphs get a
# bigger boost -- they stand alone and must be noticed at a glance. The small
# negative rise keeps the larger glyph centred on the text baseline.
ICON_SIZE="135%"
ALERT_SIZE="160%"
glyph() { printf "<span size='%s' rise='-1pt'>%s</span>" "${2:-$ICON_SIZE}" "$1"; }

prev_rx=0 prev_tx=0 prev_t=0 prev_if=""
last_json=""

emit() {
    local state conn line dev type dstate name iface="" kind="" devstate=""
    local text class tooltip signal="" freq="" ssid="" icon rate=""

    # ── Which link: a connected ethernet wins, else the Wi-Fi device ──────
    while IFS=: read -r dev type dstate name; do
        case "$type" in
            ethernet) [[ "$dstate" == connected ]] && { iface=$dev; kind=ethernet; devstate=$dstate; ssid=$name; break; } ;;
            wifi)     [[ -z "$kind" ]] && { iface=$dev; kind=wifi; devstate=$dstate; ssid=$name; } ;;
        esac
    done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null)

    conn="$(connectivity)"

    # ── Signal (Wi-Fi only; --rescan no never triggers a scan) ─────────────
    if [[ "$kind" == wifi && "$devstate" == connected ]]; then
        line=$(nmcli -t -f IN-USE,SIGNAL,FREQ,SSID dev wifi list --rescan no ifname "$iface" 2>/dev/null | grep -m1 '^\*')
        IFS=: read -r _ signal freq _ <<<"$line"
        ssid=${line#*:*:*:}
        ssid=${ssid//\\:/:}
        freq=${freq% MHz}
    fi

    # ── Speed, from the kernel's byte counters ─────────────────────────────
    if [[ -n "$iface" && -r /sys/class/net/$iface/statistics/rx_bytes ]]; then
        local rx tx now dt
        rx=$(< /sys/class/net/$iface/statistics/rx_bytes)
        tx=$(< /sys/class/net/$iface/statistics/tx_bytes)
        now=${EPOCHREALTIME/./}
        if [[ "$iface" == "$prev_if" ]] && (( prev_t > 0 )); then
            dt=$(( (now - prev_t) / 1000 ))  # ms
            (( dt > 0 )) && rate="↓ $(human_rate $(( (rx - prev_rx) * 1000 / dt )))  ↑ $(human_rate $(( (tx - prev_tx) * 1000 / dt )))"
        fi
        prev_rx=$rx prev_tx=$tx prev_t=$now prev_if=$iface
    fi

    # ── Pick the symbol ─────────────────────────────────────────────────────
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

    local sig=${signal:-0}
    case "$state" in
        full)
            if [[ "$kind" == ethernet ]]; then
                text=$(glyph "󰈀")
            else
                if   (( sig >= 75 )); then icon="󰤨"
                elif (( sig >= 50 )); then icon="󰤥"
                elif (( sig >= 25 )); then icon="󰤢"
                else                       icon="󰤟"; fi
                text="$(glyph "$icon") ${sig}%"
            fi
            tooltip="Connected · internet OK"
            ;;
        limited)      text=$(glyph "$([[ $kind == ethernet ]] && echo "󰈀" || echo "󰤫")" "$ALERT_SIZE"); tooltip="Connected, but NO INTERNET\nRight-click to re-check" ;;
        portal)       text=$(glyph "󰤬" "$ALERT_SIZE"); tooltip="Login page required\nClick to open it" ;;
        connecting)   text=$(glyph "󰤯"); tooltip="Connecting…" ;;
        disconnected) text=$(glyph "󰤮" "$ALERT_SIZE"); tooltip="Not connected\nClick for Wi-Fi settings" ;;
        off)          text=$(glyph "󰖪"); tooltip="Wi-Fi is off" ;;
    esac
    class=$state

    if [[ "$devstate" == connected ]]; then
        [[ -n "$ssid" ]] && tooltip="$(json_escape "$ssid")$([[ -n $signal ]] && echo "  ·  ${signal}%")$([[ -n $freq ]] && printf '  ·  %d.%d GHz' $((freq / 1000)) $((freq % 1000 / 100)))\n$tooltip"
        [[ -n "$rate" ]] && tooltip="$tooltip\n$rate"
    fi

    # ── Notify on internet changes only, never repeatedly ──────────────────
    local prev
    prev="$(cat "$LAST_FILE" 2>/dev/null)"
    if [[ "$state" != "$prev" ]]; then
        printf '%s\n' "$state" > "$LAST_FILE"
        case "$state" in
            limited) notify-send -u critical "Wi-Fi" "Connected, but no internet" ;;
            portal)  notify-send "Wi-Fi" "Login required -- click the Wi-Fi icon" ;;
            full)    [[ "$prev" == limited || "$prev" == portal ]] && notify-send "Wi-Fi" "Internet is back" ;;
        esac
    fi

    local json
    json=$(printf '{"text":"%s","class":"%s","tooltip":"%s"}' "$text" "$class" "$tooltip")
    if [[ "$json" != "$last_json" ]]; then
        printf '%s\n' "$json"
        last_json=$json
    fi
}

emit
exec 3< <(nmcli monitor 2>/dev/null)
monitor_pid=$!
# When waybar restarts, our next write hits a closed pipe (SIGPIPE). Take the
# nmcli monitor child down with us, or it lingers until NetworkManager's next
# event -- one stray process per waybar restart.
trap 'kill "$monitor_pid" 2>/dev/null; exit 0' PIPE TERM INT HUP
trap 'kill "$monitor_pid" 2>/dev/null' EXIT
while true; do
    read -r -t "$TICK" -u 3 _
    # 1 = EOF: NetworkManager went away. Exit and let waybar's
    # restart-interval bring us back, rather than spinning on a dead pipe.
    (( $? == 1 )) && exit 1
    # Events come in bursts (connect = several lines); settle, then read once.
    while read -r -t 0.2 -u 3 _; do :; done
    emit
done
