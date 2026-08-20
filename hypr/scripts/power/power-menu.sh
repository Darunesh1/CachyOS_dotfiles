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

lock="  Lock"
suspend="󰒲  Suspend"
logout="󰍃  Logout"
reboot="  Reboot"
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
        # Same verb hypridle uses, so both paths go through logind.
        loginctl lock-session
        ;;
    "$suspend")
        systemctl suspend
        ;;
    "$logout")
        confirm "log out" && hyprctl dispatch exit
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
