#!/usr/bin/env bash

# Wi-Fi hotspot: share this laptop's Wi-Fi with a phone or other devices.
#
#   hotspot.sh on | off | toggle | restart
#   hotspot.sh status          "on" / "off"
#   hotspot.sh init            create ~/.config/hotspot.conf with defaults
#   hotspot.sh check           "ok|<band ch>" or "no|<why not>" -- can it share now?
#   hotspot.sh waybar          JSON for waybar's custom/hotspot (always visible)
#
# Built on create_ap from linux-wifi-hotspot (AUR), which does the hard parts:
#   * a virtual AP interface on the same card, so the laptop STAYS connected to
#     its own Wi-Fi while sharing it (NetworkManager's built-in hotspot takes
#     over wlan0 and would leave nothing to share -- there is no ethernet);
#   * NAT + DHCP/DNS (dnsmasq), plus iptables accepts for exactly that, inserted
#     on start and removed on stop -- ufw drops input/forwarding otherwise.
#
# The MT7921 can run the AP and the Wi-Fi connection only on ONE channel
# ("#channels <= 1" in `iw list`), so the AP must use the channel the laptop is
# connected on -- and it may not start an AP on a DFS (radar) channel. So on a
# 5 GHz DFS network (channels 52-144) this refuses with a clear message. The
# router's 2.4 GHz network works, and so does 5 GHz on channels 36-48/149-165.
#
# Name and password live in HOTSPOT_CONF (~/.config/hotspot.conf), never in the
# repo; edit them from hotspot-menu.sh (SUPER + CTRL + H). They reach create_ap
# through a 0600 config file, not the command line, where every process on the
# machine could read the password.

HOTSPOT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hotspot.conf"
RUN_CONF="${XDG_RUNTIME_DIR:-/tmp}/hotspot-create_ap.conf"
LOG_FILE="/tmp/hotspot-create_ap.log"
SELF="$(readlink -f "$0")"

notify() { notify-send "Hotspot" "$@"; }
refresh_waybar() { pkill -RTMIN+10 waybar 2>/dev/null; }

# ── Privileged part: run through pkexec, one password prompt per action ─────
# pkexec clears the environment, so everything it needs comes as arguments.
if [[ "${1:-}" == "--as-root" ]]; then
    action=$2 conf=$3 iface=$4
    case "$action" in
        start)   exec create_ap --config "$conf" ;;
        stop)    exec create_ap --stop "$iface" ;;
        restart) create_ap --stop "$iface"; sleep 1; exec create_ap --config "$conf" ;;
    esac
    exit 1
fi

# ── Settings ────────────────────────────────────────────────────────────────
load_settings() {
    HOTSPOT_NAME="" HOTSPOT_PASSWORD=""
    if [[ ! -f "$HOTSPOT_CONF" ]]; then
        # First use: a sensible name and a random 12-character password.
        local pw
        pw=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)
        save_settings "CachyOS-Hotspot" "$pw"
    fi
    # shellcheck source=/dev/null
    source "$HOTSPOT_CONF"
}

# save_settings <name> <password> -- values shell-quoted, file private.
save_settings() {
    mkdir -p "$(dirname "$HOTSPOT_CONF")"
    ( umask 077
      printf '# Hotspot settings -- edit from the hotspot menu (SUPER + CTRL + H).\n'  > "$HOTSPOT_CONF"
      printf 'HOTSPOT_NAME=%q\nHOTSPOT_PASSWORD=%q\n' "$1" "$2"                    >> "$HOTSPOT_CONF" )
}

wifi_iface() { nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'; }

# The AP interface create_ap made, if any (iw needs no root for this).
ap_iface() { iw dev 2>/dev/null | awk '/Interface/ {i=$2} /type AP/ {print i; exit}'; }

is_on() { [[ -n "$(ap_iface)" ]]; }

# Can this laptop share its Wi-Fi right now? Sets SHARE_OK (1/0), SHARE_IFACE,
# SHARE_DESC ("2.4 GHz ch 6") and, when it can't, SHARE_REASON.
# The card's regulatory table (`iw phy phy0 channels`) flags 52-64 and 100-144
# as "Radar detection" (DFS): a hotspot may not be STARTED there, only joined.
# 1-14, 36-48 and 149-165 carry no such flag.
share_check() {
    local chan
    SHARE_OK=0 SHARE_DESC="" SHARE_REASON=""
    SHARE_IFACE=$(wifi_iface)
    if [[ -z "$SHARE_IFACE" ]]; then
        SHARE_REASON="No Wi-Fi device found."
        return
    fi
    chan=$(iw dev "$SHARE_IFACE" info 2>/dev/null | awk '/channel/ {print $2; exit}')
    if [[ -z "$chan" ]]; then
        SHARE_REASON="Not connected to Wi-Fi -- the hotspot shares this laptop's Wi-Fi connection."
        return
    fi
    if (( chan <= 14 )); then
        SHARE_DESC="2.4 GHz ch $chan"
    else
        SHARE_DESC="5 GHz ch $chan"
    fi
    if (( chan <= 14 || (chan >= 36 && chan <= 48) || (chan >= 149 && chan <= 165) )); then
        SHARE_OK=1
    else
        SHARE_REASON="Your Wi-Fi is on 5 GHz channel $chan, a radar (DFS) channel where this card may not start a hotspot. Set the router's 5 GHz channel to 36-48 or 149-165, or connect to its 2.4 GHz network."
    fi
}

# ── Actions ─────────────────────────────────────────────────────────────────
start() {
    if ! command -v create_ap >/dev/null; then
        notify -u critical "linux-wifi-hotspot is not installed" "Install it with: yay -S linux-wifi-hotspot"
        return 1
    fi
    # ("restart" is the one case where it is expected to be running already.)
    [[ "${1:-}" != restart ]] && is_on && { notify "Already on"; return 0; }

    local iface
    share_check
    if (( ! SHARE_OK )); then
        notify -u critical "Can't start the hotspot" "$SHARE_REASON"
        refresh_waybar
        return 1
    fi
    iface=$SHARE_IFACE

    load_settings
    ( umask 077
      printf 'WIFI_IFACE=%q\nINTERNET_IFACE=%q\nSSID=%q\nPASSPHRASE=%q\nDAEMONIZE=1\nDAEMON_LOGFILE=%q\n' \
          "$iface" "$iface" "$HOTSPOT_NAME" "$HOTSPOT_PASSWORD" "$LOG_FILE" > "$RUN_CONF" )

    pkexec "$SELF" --as-root "${1:-start}" "$RUN_CONF" "$iface"
    local rc=$?
    # create_ap reads its config before it daemonizes, so the copy holding
    # the password is not needed any more.
    rm -f "$RUN_CONF"
    (( rc == 0 )) || { notify "Cancelled"; return 1; }

    # create_ap daemonizes at once; hostapd can still fail a moment later.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        is_on && break
        sleep 1
    done
    if is_on; then
        notify "On: $HOTSPOT_NAME" "Password: $HOTSPOT_PASSWORD"
    else
        notify -u critical "Hotspot failed to start" "See $LOG_FILE"
    fi
    refresh_waybar
}

stop() {
    is_on || { refresh_waybar; return 0; }
    pkexec "$SELF" --as-root stop "" "$(wifi_iface)" || { notify "Cancelled"; return 1; }
    notify "Off"
    refresh_waybar
}

# Always visible: dim when off, struck through when sharing is impossible right
# now (with the reason in the tooltip), green with a device count when on.
json_escape() { local s=${1//\\/\\\\}; printf '%s' "${s//\"/\\\"}"; }

waybar_json() {
    local ap clients=0
    ap=$(ap_iface)
    if [[ -n "$ap" ]]; then
        load_settings
        clients=$(iw dev "$ap" station dump 2>/dev/null | grep -c '^Station')
        printf '{"text":"󰀂 %s","class":"on","tooltip":"Hotspot ON: %s\\n%s device(s) connected\\nClick for the hotspot menu"}\n' \
            "$clients" "$(json_escape "$HOTSPOT_NAME")" "$clients"
        return
    fi
    share_check
    if (( SHARE_OK )); then
        printf '{"text":"󰀂","class":"off","tooltip":"Hotspot off · ready to share (%s)\\nClick for the hotspot menu"}\n' "$SHARE_DESC"
    else
        printf '{"text":"󰀂","class":"unavailable","tooltip":"Hotspot off · can'"'"'t share right now\\n%s\\nClick for the hotspot menu"}\n' \
            "$(json_escape "$SHARE_REASON")"
    fi
}

case "${1:-toggle}" in
    on)      start ;;
    off)     stop ;;
    toggle)  if is_on; then stop; else start; fi ;;
    restart) if is_on; then start restart; fi ;;
    status)  if is_on; then echo on; else echo off; fi ;;
    init)    load_settings ;;   # create ~/.config/hotspot.conf with defaults if missing
    check)   share_check      # "ok|2.4 GHz ch 6" or "no|<reason>", for the menu
             if (( SHARE_OK )); then echo "ok|$SHARE_DESC"; else echo "no|$SHARE_REASON"; fi ;;
    waybar)  waybar_json ;;
    *)       echo "Usage: $0 on|off|toggle|restart|status|waybar" >&2; exit 1 ;;
esac
