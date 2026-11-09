---
status: "accepted"
date: 2026-11-06
decision-makers: darriour
---

# Drive Ventoy through its web UI, not the GTK GUI

## Context and Problem Statement

`ventoy-bin` ships `/usr/share/applications/ventoy.desktop` with
`Exec=ventoygui`, and it does nothing on this machine. `VentoyGUI.x86_64`
re-execs itself through pkexec so the GTK3 frontend runs as **root**, and that
hand-off cannot work here.

## Decision Drivers

* Wayland session; root has no route to the display.
* The tool is needed rarely but must work when it is.
* Writing a USB stick is destructive, so the UI must show the device clearly.

## Considered Options

* Fix the GTK GUI by authorising root on the X display:
  `xhost +SI:localuser:root`.
* `Ventoy2Disk.sh` on the command line.
* `ventoyweb` — the bundled HTTP server plus the user's own browser.

## Decision Outcome

Chosen option: **`ventoyweb`**. It runs `tool/x86_64/V2DServer` on
`127.0.0.1:24680` and nothing else, so the privileged half is **headless** and
never touches a display. The UI is the user's own unprivileged browser.

Why the GUI cannot work, measured rather than assumed:

```
$ strings /usr/bin/pkexec | grep -xE 'DISPLAY|XAUTHORITY|LANG|PATH'
DISPLAY  LANG  PATH  XAUTHORITY        # the entire forwarded environment
$ echo "[$XAUTHORITY]"; ls ~/.Xauthority
[]                                      # unset, and no file
$ xhost
access control enabled, only authorized clients can connect
SI:localuser:darriour                   # one entry, and root is not it
```

root is not `darriour` and inherits no cookie, so `Ventoy2Disk.gtk3` cannot
open `:1`. It dies before doing any work — `/var/log/ventoy.log` is never
created, which is the tell.

`xhost +SI:localuser:root` was rejected: it lets **every** root process read
the whole X display, including keystrokes and screen contents of any X11
client, until logout, and it must be repeated each session. That is a real
security loosening for a tool used a few times a year.

The CLI was rejected as the default because the target device is typed by hand
into a destructive flag.

### Consequences

* Good, because no root process ever needs display access.
* Good, because the device name and size are shown in the browser before
  Install.
* Bad, because a terminal must stay open for the whole write, and a browser tab
  is needed on an 8 GB machine where two browsers already hold ~3.47 GB.
* Bad, because the entry must keep the packaged basename `ventoy.desktop` to
  shadow the broken one; renaming it brings the broken row back.

### Confirmation

```sh
python3 -c "import gi; gi.require_version('Gio','2.0'); from gi.repository import Gio; \
    print(Gio.DesktopAppInfo.new('ventoy.desktop').get_filename())"
# -> /home/darriour/.local/share/applications/ventoy.desktop
ss -ltnp | grep 24680     # must be 127.0.0.1:24680, never 0.0.0.0
```

`./install.sh --check` carries a `ventoy launcher` row testing the whole chain.

## More Information

Mechanism, the no-USB guard and the write warning are in
[../system/README.md](../system/README.md). Commit `7b9c3c1`.
