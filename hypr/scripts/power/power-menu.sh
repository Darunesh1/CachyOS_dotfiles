#!/usr/bin/env bash

# Power menu. Replaces wlogout, so the whole desktop uses one menu system.
#
# Two deliberate differences from the old wlogout layout:
#
#   Logout runs `hyprctl dispatch exit`, not `loginctl terminate-user`. The
#   latter maps to org.freedesktop.login1.manage, which polkit rates
#   auth_admin_keep -- it demanded a password just to log out, and silently did
#   nothing when no polkit agent was running.
#
#   Hibernate is gone. It cannot resume on this machine: no `resume=` kernel
#   parameter, no `resume` hook in mkinitcpio.conf, and /swapfile is smaller
#   than RAM. An entry that cannot work is worse than no entry.

THEME="$HOME/.config/rofi/themes/powermenu.rasi"

lock="󰌾  Lock"
suspend="󰒲  Suspend"
logout="󰍃  Logout"
reboot="󰜉  Reboot"
shutdown="⏻  Shutdown"

# rofi commits on Enter, unlike wlogout's click-a-big-button. Anything that
# loses unsaved work asks first, with "No" listed first so it is the default and
# Enter-Enter cancels rather than commits.
confirm() {
    local answer
    answer=$(printf '󰅖  No\n󰄬  Yes, %s\n' "$1" \
        | rofi -dmenu -i -p "Confirm" -theme "$THEME")
    [[ "$answer" == *"Yes"* ]]
}

selected=$(printf '%s\n%s\n%s\n%s\n%s\n' \
    "$lock" "$suspend" "$logout" "$reboot" "$shutdown" \
    | rofi -dmenu -i -p "Power" -theme "$THEME")

case "$selected" in
    "$lock")
        # Call hyprlock directly rather than `loginctl lock-session`. The latter
        # only emits a logind signal, and the thing that listens for it here is
        # hypridle -- which Coffee Mode deliberately stops. Locking on request
        # must not depend on idle handling being enabled.
        # `pidof ||` guards against stacking instances, as hypridle.conf does.
        pidof hyprlock >/dev/null || hyprlock &
        ;;
    "$suspend")
        systemctl suspend
        ;;
    "$logout")
        # Lua syntax: hyprctl wraps its dispatch argument in hl.dispatch() and
        # evaluates it as Lua, and there is no global named `exit`, so the old
        # `hyprctl dispatch exit` silently failed.
        confirm "log out" && hyprctl dispatch 'hl.dsp.exit()'
        ;;
    "$reboot")
        confirm "reboot" && systemctl reboot
        ;;
    "$shutdown")
        confirm "shut down" && systemctl poweroff
        ;;
    *)
        # Empty selection means Escape was pressed. Do nothing.
        exit 0
        ;;
esac
