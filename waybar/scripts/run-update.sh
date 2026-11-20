#!/usr/bin/env bash
#
# run-update.sh -- the waybar update badge's click action (waybar/config.jsonc).
# Runs inside a terminal started with `kitty -e`, which CLOSES the moment the
# command exits. So this ends by waiting for Enter: the result and any error stay
# on screen until you have read them.
#
#   1. sudo pacman -Syu     repo packages (asks [Y/n]; no --noconfirm on purpose)
#   2. yay -Sua             AUR packages, only if step 1 worked (asks first)
#   3. summary              results, NEW .pacnew files, reboot hint
#   4. refresh the badge    waybar signal 11, so the count is not stale for an hour
#
# RUN_UPDATE_DRY=1 prints what would run instead of running it (for testing).

set -u

SIGNAL=11   # must match "signal" on custom/updates in config.jsonc
KERNEL_PKG=linux-cachyos
DRY="${RUN_UPDATE_DRY:-}"

run() {
    if [[ -n "$DRY" ]]; then echo "[dry run] $*"; return 0; fi
    "$@"
}

pacnew_list() { find /etc -name '*.pacnew' 2>/dev/null | sort; }

# Ctrl-C stops the running step, not this script: the wait at the end still happens.
trap ':' INT

before=$(pacnew_list)

echo "== Repo packages: sudo pacman -Syu"
run sudo pacman -Syu
pac_rc=$?

aur_rc="skipped"
if [[ $pac_rc -eq 0 ]]; then
    echo
    echo "== AUR packages: yay -Sua"
    if command -v yay >/dev/null; then
        run yay -Sua
        aur_rc=$?
    else
        aur_rc="yay not installed"
    fi
fi

echo
echo "== Summary"
[[ $pac_rc -eq 0 ]] && echo "  pacman: ok" || echo "  pacman: FAILED (exit $pac_rc)"
case "$aur_rc" in
    0)       echo "  AUR:    ok" ;;
    skipped) echo "  AUR:    skipped because pacman failed" ;;
    *[!0-9]*) echo "  AUR:    $aur_rc" ;;
    *)       echo "  AUR:    FAILED (exit $aur_rc)" ;;
esac

# Only files that appeared during this run: older ones are already known and listing
# them every time would teach you to ignore the line.
new=$(comm -13 <(printf '%s\n' "$before") <(pacnew_list))
if [[ -n "$new" ]]; then
    echo "  NEW .pacnew files (a config was not overwritten; merge with pacdiff):"
    printf '    %s\n' $new
fi

# The kernel on disk changed but the running one did not: modules for the old one may
# already be gone, so say it plainly.
installed=$(pacman -Q "$KERNEL_PKG" 2>/dev/null | awk '{print $2}')
if [[ -n "$installed" && "$(uname -r)" != "$installed"* ]]; then
    echo "  REBOOT recommended: running $(uname -r), installed $installed"
fi

# The badge only re-reads its count on a timer (hourly) unless poked. A real-time signal
# nobody handles terminates a process by default. waybar's /proc/PID/status (SigCgt) shows
# it catches nearly all of them, so an unknown one is probably ignored, but that was not
# tested by sending one, so: send it only when the running waybar started AFTER the config
# that declares the signal was last changed (the config is read once, at start).
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"
wb=$(pgrep -xo waybar)
if [[ -n "$wb" && -z "$DRY" ]] && grep -qE "\"signal\":[[:space:]]*$SIGNAL\b" "$cfg" 2>/dev/null; then
    wb_start=$(( $(date +%s) - $(ps -o etimes= -p "$wb") ))   # /proc/PID mtime is not a start time
    if [[ "$wb_start" -gt "$(stat -L -c %Y "$cfg")" ]]; then
        pkill -RTMIN+"$SIGNAL" -x waybar
    else
        echo "  (badge not refreshed: waybar predates its config; restart waybar once)"
    fi
fi

echo
read -rp "Press Enter to close this window" _
[[ $pac_rc -ne 0 ]] && exit "$pac_rc"
[[ "$aur_rc" =~ ^[0-9]+$ ]] && exit "$aur_rc"
exit 0
