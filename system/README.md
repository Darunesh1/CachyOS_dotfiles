# system

System-level configuration that lives outside `~/.config`. Most of it needs
`sudo` to install, and most of it exists for one reason: **systemd-oomd killed
the entire desktop, twice, while it was being used.** (`ventoy/` is the
exception, and is documented at the bottom.)

```
Sep 28 15:04:46  systemd-oomd: Marked .../wayland-wm@hyprland.desktop.service for killing
                 due to memory used (7177072640) / total (7969300480) and
                 swap used (7503994880) / total (7969173504) being more than 90.00%
Sep 28 15:04:46  wayland-wm@hyprland.desktop.service: Failed with result 'oom-kill'
Sep 29 11:42:06  ... identical, swap used (7186481152)
```

Both times the session disappeared to the login screen with everything open
inside it. Four separate things lined up to make that possible, and the fourth
is the one that makes the other fixes stick.

## 1. The swap rule was written for a disk, and this machine has no disk swap

Arch ships `ManagedOOMSwap=kill` on every user slice
(`/usr/lib/systemd/system/user-.slice.d/10-oomd-per-slice-defaults.conf`).
It means: when total swap use passes 90%, kill the monitored cgroup using the
most swap.

That is sound advice when swap is a partition on an SSD. Here the **only** swap
was zram, sized at 100% of RAM by `/usr/lib/systemd/zram-generator.conf`
(`zram-size = ram`). zram is compressed RAM — so "swap 90% full" describes a
busy 8 GB laptop, not a machine about to wedge, and oomd was pulling the trigger
on a false alarm.

`oomd/90-no-swap-kill.conf` sets `ManagedOOMSwap=auto` for user slices, which
switches off that one heuristic. Memory pressure (PSI) is *not* abandoned — it
measures processes actually stalling on memory, which is the signal worth acting
on — but it had to **move**, for the reason in section 4.

### Why oomd was running at all

`systemd-oomd` is `disabled` in the presets on this machine and was never
enabled by hand. It ran anyway:

```
$ systemctl show systemd-oomd -p WantedBy
WantedBy=user-1000.slice
```

A unit carrying `ManagedOOM*` settings gains an implicit dependency on oomd. So
that one `cachyos-settings` file both starts the killer and arms it. **This is
also the answer to "why did plain Arch never do this to me?"** — on plain Arch
neither `10-oomd-per-slice-defaults.conf` nor `zram-generator.conf` exists (both
are `cachyos-settings`, verified with `pacman -Qo`), so oomd never starts and
there is no zram. Memory exhaustion fell to the kernel OOM killer, which kills a
single process by score rather than a whole cgroup, and left the compositor
alone.

## 2. There was no real swap at all

`swapon --show` listed `/dev/zram0` and nothing else, on a disk with 361 GB
free. zram buys 2–3x on compressible pages and then the machine is simply out
of memory.

`swap/setup-swapfile.sh` adds a disk swapfile at low priority, so the kernel
fills fast zram first (`pri=100`) and only reaches for the file (`pri=10`) when
zram is genuinely exhausted.

btrfs makes swapfiles awkward — they must not be copy-on-write, must not be
compressed, and must not live anywhere that gets snapshotted, since snapper
snapshots `@` on every pacman transaction and a snapshotted swapfile is a
corrupt one. The script handles both halves: a dedicated **`@swap` subvolume**
created from the filesystem's top level (a sibling of `@`, so outside snapper's
reach), and `btrfs filesystem mkswapfile`, which sets NODATACOW and disables
compression by itself.

## 3. The desktop and the apps were the same cgroup

This is the part that made a memory shortage fatal rather than annoying. oomd
kills *cgroups*, and anything Hyprland spawns directly inherits its cgroup:

```
firefox  pid 9109   .../session.slice/wayland-wm@hyprland.desktop.service
kitty    pid 2332   .../session.slice/wayland-wm@hyprland.desktop.service
```

So Firefox, the terminal and the compositor were one cgroup holding nearly all
the memory on the machine. There was no way for oomd to reclaim anything
*except* by killing the desktop. Marking the compositor as
`ManagedOOMPreference=avoid` would not have helped **at this point**: with
everything in one cgroup there was no other candidate to prefer, so the flag
would have looked like a fix and changed nothing. It only became worth setting
once the apps moved out — which is section 4.

The fix is in `hypr/config/lib.lua` instead: `L.app()` wraps a command in
`uwsm app --`, giving it its own scope under `app.slice`
(`app-Hyprland-firefox-<hash>.scope`). `hypr/config/binds.lua` uses it for the
four memory-hungry launches — terminal, file manager, Firefox, and the rofi
launcher (that last one matters because apps started *from* rofi inherit
rofi's cgroup). The ~32 script and menu binds are deliberately left alone: they
use almost no memory, and a shell script in its own scope can see a different
environment than one inheriting the session's — a real risk for the ones
calling `hyprctl` and `notify-send`.

## 4. The protection was ignored because of who owns a directory

Sections 1–3 stopped the session being killed *for the wrong reason*. They did
not stop `ManagedOOMMemoryPressure=kill` — the rule worth keeping — from picking
the desktop when memory really does run short.

The obvious answer is `ManagedOOMPreference=avoid` on the compositor. On its own
it does nothing, and nothing *visibly*: systemd sets the extended attribute,
oomd reads it, and throws it away. From `man 5 systemd.resource-control`:

> When calculating candidates to relieve memory pressure, systemd-oomd will only
> respect these extended attributes if the unit's cgroup is owned by root, or if
> the unit's cgroup owner, and the owner of the monitored ancestor cgroup are the
> same.

Measured here with `stat -c '%U:%G'`:

```
root:root   /sys/fs/cgroup/user.slice/user-1000.slice                        <- the monitor
darriour    /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service
darriour    .../user@1000.service/session.slice/wayland-wm@hyprland.desktop.service  <- the candidate
```

CachyOS sets the rule on `user-.slice`, which is **root-owned**, while every
candidate inside it belongs to the user. Different owners, so `avoid` is
discarded and the desktop stays a legal target no matter what it asks for.

The fix is to move the monitoring down one level, to the user-owned
`user@.service`:

| file | installed to | does |
|---|---|---|
| `oomd/90-no-swap-kill.conf` | `/etc/systemd/system/user-.slice.d/90-no-swap-kill.conf` | both rules `auto` — stop monitoring from the root-owned slice |
| `oomd/90-user-manager-oom.conf` | `/etc/systemd/system/user@.service.d/90-oom.conf` | pressure monitoring back at the same 80%, now user-owned |
| `oomd/90-compositor-oom.conf` | `~/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/90-oom.conf` | `ManagedOOMPreference=avoid` |

Monitor and candidates now share an owner, so the flag is honoured. **All three
are required** — any one alone is a no-op that looks like a fix.

`avoid` rather than `omit` is deliberate. `omit` means "never a candidate", which
sounds stronger and is worse: if something *inside* the desktop is the leak
(waybar, swaync, awww-daemon), oomd can take no action on the one cgroup that
matters, the machine grinds, and the kernel OOM killer then picks by `oom_score`
with no notion of what a compositor is — Hyprland is a plausible victim. So
`omit` does not reliably save the desktop *and* forfeits the early reaction.
With `avoid`, a Firefox scope dies first; and if the desktop genuinely is the
memory hog, killing it is the right answer to a bug worth fixing.

## Installing

```sh
# 1. the three oomd drop-ins
sudo install -Dm644 oomd/90-no-swap-kill.conf \
    /etc/systemd/system/user-.slice.d/90-no-swap-kill.conf
sudo install -Dm644 oomd/90-user-manager-oom.conf \
    /etc/systemd/system/user@.service.d/90-oom.conf
install -Dm644 oomd/90-compositor-oom.conf \
    ~/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/90-oom.conf
sudo systemctl daemon-reload && systemctl --user daemon-reload
sudo systemctl restart systemd-oomd

# 2. disk swap
sudo ./swap/setup-swapfile.sh            # 8 GiB, or --size 16G

# 3. the cgroup split -- reload Hyprland, then log out and back in
hyprctl reload
```

`install.sh` stage 8 offers all of this.

## Checking it worked

```sh
systemctl show user-1000.slice -p ManagedOOMSwap -p ManagedOOMMemoryPressure  # both auto
systemctl show user@1000.service -p ManagedOOMMemoryPressure                  # kill
swapon --show                                        # zram0 pri 100 + swapfile pri 10
pgrep -x firefox | xargs -I{} cat /proc/{}/cgroup    # app.slice/app-Hyprland-firefox-*.scope

# The only check that distinguishes a working setup from a convincing no-op:
getfattr -d -m 'user.oomd' \
  /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/session.slice/wayland-wm@hyprland.desktop.service
# -> user.oomd_avoid="1"
```

`install.sh --check` runs all of these.

The last two matter most. **Empty `getfattr` output means the protection is not
real**, whatever the other settings say. Measured: `systemctl --user
daemon-reload` writes the attribute onto the running compositor's cgroup
immediately, so it does not wait for a logout. And if Firefox
still reports `wayland-wm@hyprland.desktop.service`, it was started by something
unwrapped — a rofi launcher predating this change, or an autostart entry — so
there is no candidate for oomd to prefer over the desktop.

## Undoing

```sh
sudo rm /etc/systemd/system/user-.slice.d/90-no-swap-kill.conf
sudo rm /etc/systemd/system/user@.service.d/90-oom.conf
rm ~/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/90-oom.conf
sudo systemctl daemon-reload && systemctl --user daemon-reload
sudo systemctl restart systemd-oomd
sudo ./swap/setup-swapfile.sh --remove
```

`setup-swapfile.sh` backs up `/etc/fstab` before every edit
(`/etc/fstab.bak.<timestamp>`) and leaves the `@swap` subvolume in place on
`--remove`, so putting the file back later costs one `mkswapfile`.

## What this does not fix

8 GB is still 8 GB. Firefox, a browser full of tabs, Claude Code, a JVM and
Docker (~250 MB, left enabled by choice) do not fit comfortably, and they never
will. What changed is the failure mode: the machine now pages to disk instead of
hitting a wall, and when something must die it is one app rather than the whole
session.

---

# ventoy/ — a working launcher for Ventoy

`ventoy-bin` ships `/usr/share/applications/ventoy.desktop` with
`Exec=ventoygui`. **That can never work on this machine**, so do not "fix" the
launcher back to it.

`VentoyGUI.x86_64` re-execs itself through pkexec — its own strings carry
`try restart self by pkexec ...` and `We have root privileges, just exec %s` —
so the GTK3 frontend runs as **root**. Three measurements explain why that
dies:

```
$ strings /usr/bin/pkexec | grep -xE 'DISPLAY|XAUTHORITY|LANG|PATH'
DISPLAY  LANG  PATH  XAUTHORITY        # the entire forwarded environment

$ echo "[$XAUTHORITY]"; ls ~/.Xauthority
[]                                      # unset
ls: cannot access '/home/darriour/.Xauthority': No such file or directory

$ xhost
access control enabled, only authorized clients can connect
SI:localuser:darriour                   # one entry, and root is not it
```

root is not `darriour` and inherits no cookie, so `tool/x86_64/Ventoy2Disk.gtk3`
cannot open `:1`. It dies before doing any work — `/var/log/ventoy.log` is never
even created, which is the tell. Not the cause: missing libraries (`ldd` on
`Ventoy2Disk.gtk3` and `.qt5` reports zero `not found`), an unset `DISPLAY`
(it is `:1`, Xwayland is up), or polkit (`polkitd` and
`polkit-gnome-authentication-agent-1` both run fine).

## The fix

`ventoyweb` instead. It starts `tool/x86_64/V2DServer` on `127.0.0.1:24680` and
nothing else, so the privileged half is **headless** — it never touches a
display, and pkexec is perfectly fine for it. The UI is your own unprivileged
browser. Same Ventoy code underneath, no root GUI.

| file | installed to | does |
|---|---|---|
| `ventoy/ventoy-web.sh` | stays in the repo, run from the entry below | checks a USB disk exists, starts the server under pkexec, opens the browser |
| `ventoy/ventoy.desktop` | `~/.local/share/applications/ventoy.desktop` | the rofi entry; generated by `install.sh`, not symlinked |

Two details that are load-bearing:

- **The basename must stay `ventoy.desktop`.** `XDG_DATA_DIRS` is
  `~/.local/share:/usr/local/share:/usr/share`, home first, so this file
  *shadows* the packaged one and launchers see a single Ventoy row. Verified
  with the real XDG lookup rather than by reading the spec:
  ```
  $ python3 -c "import gi; gi.require_version('Gio','2.0'); from gi.repository import Gio; \
      print(Gio.DesktopAppInfo.new('ventoy.desktop').get_filename())"
  /home/darriour/.local/share/applications/ventoy.desktop
  ```
  Rename it and the broken `Exec=ventoygui` entry comes back alongside this one.
- **The entry is generated, not symlinked**, because `Exec=` needs the absolute
  repo path baked in — same reason `write_restore_script` generates its file.
  `install.sh` substitutes the placeholder in stage 4.

The server runs in the **foreground** of a `kitty --class ventoy-web --hold`
window on purpose. Something has to own its lifetime, and there is no way to
detect "the user closed the browser tab"; a silent background launch would leave
a root HTTP server listening indefinitely. Ctrl+C or closing the window stops
it. `hypr/config/rules.lua` floats that class at 900x520, centred (measured:
`floating: true`, `size: [900, 520]`, `at: [510, 301]` on a 1920-wide output).

`-H 127.0.0.1` is passed explicitly rather than trusting the script's default,
so the root HTTP server is never reachable off this machine. Check with
`ss -ltnp | grep 24680` — it must say `127.0.0.1:24680`, never `0.0.0.0`.

The script refuses before pkexec when no USB disk is present:

```
$ ./ventoy/ventoy-web.sh
No USB drive found. Plug the stick in, then launch Ventoy again.
```

That guard exists because Ventoy2Disk enumerates removable USB disks only, so
with nothing plugged in its device list is empty and Install is inert — which is
indistinguishable from "Ventoy is broken". Being told to plug the stick in beats
being asked for a password and then shown an empty list.

## Checking it worked

```sh
desktop-file-validate ~/.local/share/applications/ventoy.desktop   # no output
grep Exec ~/.local/share/applications/ventoy.desktop               # path must exist
hyprctl clients -j | jq -r '.[] | select(.class=="ventoy-web") | .floating'
ss -ltnp | grep 24680                                              # 127.0.0.1 only
```

`install.sh --check` carries a `ventoy launcher` row that tests the whole chain
— the override exists, its `Exec=` target is executable, and `ventoyweb` is on
`PATH` — because a stale path or a missing binary both fail silently from rofi.

## If you ever want the native window back

The only route is `xhost +SI:localuser:root` before launching `ventoygui`. That
lets **every root process on the machine read the whole X display**, including
keystrokes and screen contents of any X11 client, until you log out, and it has
to be repeated each session. The web UI avoids that trade entirely, which is why
it is the default here.

## Writing a stick

Ventoy's Install rewrites the partition table of the **whole device** — every
file and every existing partition on it is destroyed, with no undo. Match the
device name and size in the web UI against `lsblk -o NAME,SIZE,TRAN,RM,MODEL`
before pressing it, and unmount the stick first (`sudo umount /dev/sda1`) since
Ventoy repartitions the entire disk. Leave Secure Boot support off unless the
target machine actually enforces it.
