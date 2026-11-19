#!/usr/bin/env bash
#
# Snooze / Dismiss buttons for notifications whose app does not draw any.
# Run by swaync (config.json "scripts"); see swaync/README.md, "Buttons".
#
#   notify-actions.sh timer      kclock "Timer complete": a Dismiss button
#   notify-actions.sh reminder   renCal reminder: Snooze 10 min and Dismiss
#
# Why: kclock's finished-timer notification only has a click-the-body action, and
# renCal has no snooze at all, and swaync draws only real buttons. swaync cannot add
# a button to another app's notification, so this sends a SECOND notification of its
# own with the buttons, waits for the click, and acts on it.
#
# swaync passes the original notification in SWAYNC_* variables. The helper's own
# popup uses app-name "notify-actions", which config.json matches first and ignores,
# otherwise it would trigger this script again.

set -u

kind="${1:-}"
SNOOZE_MIN="${NOTIFY_SNOOZE_MIN:-10}"
summary="${SWAYNC_SUMMARY:-Reminder}"
body="${SWAYNC_BODY:-}"
orig_id="${SWAYNC_ID:-}"

# swaync waits for its scripts, and notify-send --wait blocks until a click, so the
# real work runs detached and this returns at once.
if [[ "${NOTIFY_ACTIONS_DETACHED:-}" != 1 ]]; then
    NOTIFY_ACTIONS_DETACHED=1 setsid -f "$0" "$@" </dev/null >/dev/null 2>&1
    exit 0
fi

# Close the original notification once the user has answered.
close_original() {
    [[ "$orig_id" =~ ^[0-9]+$ ]] && swaync-client --close-notification "$orig_id" >/dev/null 2>&1
    return 0
}

# kclock keeps ringing until told to stop. Find the timer that is ringing and dismiss it.
dismiss_timers() {
    local path
    while read -r path; do
        [[ "$(busctl --user get-property org.kde.kclockd "$path" org.kde.kclock.Timer ringing 2>/dev/null)" == "b true" ]] &&
            busctl --user call org.kde.kclockd "$path" org.kde.kclock.Timer dismiss >/dev/null 2>&1
    done < <(busctl --user tree org.kde.kclockd --list 2>/dev/null | grep '^/Timers/')
}

case "$kind" in
    timer)
        answer=$(notify-send --app-name=notify-actions --expire-time=0 --urgency=critical --wait \
            --icon=org.kde.kclock --action=dismiss=Dismiss "$summary" "$body" 2>/dev/null)
        [[ "$answer" == dismiss ]] && { dismiss_timers; close_original; }
        ;;
    reminder)
        answer=$(notify-send --app-name=notify-actions --expire-time=0 --wait \
            --icon=appointment-soon --action="snooze=Snooze $SNOOZE_MIN min" --action=dismiss=Dismiss \
            "$summary" "$body" 2>/dev/null)
        case "$answer" in
            snooze)
                close_original
                # A one-shot user timer: survives this script, needs no daemon of ours.
                # Fires through the normal rencal path, so it plays the sound and gets
                # the buttons again.
                systemd-run --user --quiet --on-active="${SNOOZE_MIN}m" \
                    notify-send --app-name=rencal --expire-time=0 "$summary" "$body"
                ;;
            dismiss) close_original ;;
        esac
        ;;
    *)
        echo "usage: ${0##*/} timer|reminder" >&2
        exit 2
        ;;
esac
exit 0
