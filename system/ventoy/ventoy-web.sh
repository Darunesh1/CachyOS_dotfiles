#!/usr/bin/env bash
#
# Launch Ventoy's web UI. Called from ~/.local/share/applications/ventoy.desktop,
# which install.sh generates from system/ventoy/ventoy.desktop.
#
# WHY THIS EXISTS -- do not "simplify" it back to `ventoygui`.
#
# The packaged /usr/share/applications/ventoy.desktop runs `ventoygui`, which
# cannot work on this machine. VentoyGUI.x86_64 re-execs itself through pkexec
# (its own strings: "try restart self by pkexec ...") so the GTK3 frontend runs
# as root. That hand-off dies here:
#
#   * pkexec forwards only DISPLAY, LANG, PATH, XAUTHORITY
#     (measured: strings /usr/bin/pkexec)
#   * XAUTHORITY is empty and ~/.Xauthority does not exist
#   * xhost reports "access control enabled, only authorized clients can
#     connect" with one entry, SI:localuser:darriour
#
# root is not darriour and holds no cookie, so tool/x86_64/Ventoy2Disk.gtk3
# never opens a window and /var/log/ventoy.log is never even created.
#
# ventoyweb has no such problem. It runs tool/x86_64/V2DServer and nothing
# else, so the privileged half is HEADLESS -- it never touches a display, and
# pkexec is perfectly fine for it. The UI is the user's own unprivileged
# browser. Same Ventoy code underneath, no root GUI.

set -u

PORT=24680
HOST=127.0.0.1
URL="http://${HOST}:${PORT}"

die() {
    notify-send -a Ventoy -i ventoy -u critical "Ventoy" "$1"
    printf '\n%s\n\n' "$1" >&2
    exit 1
}

# ── 1. No stick, no point ──────────────────────────────────────────────────
# Ventoy2Disk enumerates removable USB disks only. Without one its device list
# is empty and Install is inert, which is indistinguishable from "Ventoy is
# broken". Say so plainly instead, and do it BEFORE pkexec so the user is not
# asked for a password just to be told to plug something in.
usb=$(lsblk -dn -o NAME,TRAN,RM,SIZE,MODEL 2>/dev/null | awk '$2 == "usb" && $3 == 1')
if [[ -z "$usb" ]]; then
    die "No USB drive found. Plug the stick in, then launch Ventoy again."
fi

printf 'USB devices Ventoy can write to:\n%s\n\n' "$usb"

# ── 2. Reuse a server that is already up ───────────────────────────────────
# VentoyWeb.sh refuses to start a second instance ("Another ventoy server is
# running now, please close it first."), so probe before asking for a password.
if curl -sS --max-time 1 -o /dev/null "$URL" 2>/dev/null; then
    printf 'Ventoy server already running. Opening %s\n' "$URL"
    xdg-open "$URL" >/dev/null 2>&1
    exit 0
fi

# ── 3. Open the browser once the port actually answers ─────────────────────
# Opening it before V2DServer binds shows a connection error, so poll. ~10 s
# at 0.2 s intervals; the server normally binds in under a second.
(
    for _ in $(seq 1 50); do
        if curl -sS --max-time 1 -o /dev/null "$URL" 2>/dev/null; then
            xdg-open "$URL" >/dev/null 2>&1
            exit 0
        fi
        sleep 0.2
    done
    notify-send -a Ventoy -i ventoy -u critical "Ventoy" \
        "Server did not come up on $URL. Check this terminal for the reason."
) &

# ── 4. The server owns the foreground ──────────────────────────────────────
# Foreground on purpose: something has to own the server's lifetime, and there
# is no way to detect "the user closed the browser tab". Ctrl+C or closing this
# window stops the root HTTP server. -H is passed explicitly rather than
# trusting the script default, so it is never reachable off this machine.
printf 'Starting Ventoy server on %s -- press Ctrl+C here when you are done.\n\n' "$URL"
exec pkexec /usr/bin/ventoyweb -H "$HOST" -p "$PORT"
