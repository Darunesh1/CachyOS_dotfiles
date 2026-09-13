#!/usr/bin/env bash

# Waybar custom/internet: a badge that appears only when Wi-Fi is connected
# but the internet is not reachable.
#
# The built-in network module only knows whether the link is up. NetworkManager
# additionally runs a connectivity check (http://ping.archlinux.org/nm-check.txt,
# from /usr/lib/NetworkManager/conf.d/20-connectivity.conf) and reports:
#   full     internet works             -> no badge
#   limited  link up, no internet       -> red "no internet"
#   portal   a login page is in the way -> yellow "login"
#   none / unknown                      -> no badge (the network module
#                                          already shows "off")
#
# Event driven: prints once, then re-reads the state only when `nmcli monitor`
# reports a change, so it costs nothing while idle. How quickly a drop *during*
# a session is noticed depends on NetworkManager's check interval
# (packages/NetworkManager/30-connectivity-interval.conf -> 60 s).
#
#   internet-status.sh          stream JSON for waybar
#   internet-status.sh --click  re-check now; open the login page if in a portal

LAST_FILE="${XDG_RUNTIME_DIR:-/tmp}/internet-status.last"
PORTAL_URL="http://neverssl.com"

connectivity() { nmcli -t -f CONNECTIVITY general 2>/dev/null; }

if [[ "${1:-}" == "--click" ]]; then
    [[ "$(connectivity)" == "portal" ]] && xdg-open "$PORTAL_URL" >/dev/null 2>&1 &
    # Force NetworkManager to re-check now; the monitor loop picks up the result.
    nmcli networking connectivity check >/dev/null 2>&1
    exit 0
fi

last_json=""

emit() {
    local state text="" class tooltip="" prev json
    state="$(connectivity)"
    class="${state:-unknown}"

    case "$state" in
        limited)
            text="󰤫 no internet"
            tooltip="Wi-Fi is connected, but there is no internet.\nClick to re-check."
            ;;
        portal)
            text="󰤩 login"
            tooltip="A login page is blocking the internet.\nClick to open it."
            ;;
    esac

    # Notify on changes only -- not on every event, and not again after a
    # waybar restart while the state is unchanged.
    prev="$(cat "$LAST_FILE" 2>/dev/null)"
    if [[ "$state" != "$prev" ]]; then
        printf '%s\n' "$state" > "$LAST_FILE"
        case "$state" in
            limited) notify-send -u critical "Wi-Fi" "Connected, but no internet" ;;
            portal)  notify-send "Wi-Fi" "Login required -- click the 󰤩 login badge" ;;
            full)    [[ "$prev" == limited || "$prev" == portal ]] && notify-send "Wi-Fi" "Internet is back" ;;
        esac
    fi

    json=$(printf '{"text":"%s","class":"%s","tooltip":"%s"}' "$text" "$class" "$tooltip")
    if [[ "$json" != "$last_json" ]]; then
        printf '%s\n' "$json"
        last_json="$json"
    fi
}

emit
# Any NetworkManager event can mean a connectivity change ("Connectivity is now
# 'limited'", a reconnect, a new access point); re-reading is cheap, and emit
# only prints when something actually changed.
nmcli monitor 2>/dev/null | while IFS= read -r _; do
    emit
done
