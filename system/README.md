# system

System-level configuration that lives outside `~/.config` and therefore needs
`sudo` to install. Everything here exists for one reason: **systemd-oomd killed
the entire desktop, twice, while it was being used.**

```
Sep 28 15:04:46  systemd-oomd: Marked .../wayland-wm@hyprland.desktop.service for killing
                 due to memory used (7177072640) / total (7969300480) and
                 swap used (7503994880) / total (7969173504) being more than 90.00%
Sep 28 15:04:46  wayland-wm@hyprland.desktop.service: Failed with result 'oom-kill'
Sep 29 11:42:06  ... identical, swap used (7186481152)
```

Both times the session disappeared to the login screen with everything open
inside it. Three separate mistakes lined up to make that possible.

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
switches off that one heuristic. **`ManagedOOMMemoryPressure=kill` is left at
its default on purpose** — memory pressure (PSI) measures processes actually
stalling on memory, which is the signal worth acting on.

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
*except* by killing the desktop — and marking the compositor as
`ManagedOOMPreference=avoid` would not have helped, because with everything in
one cgroup there was no other candidate. That is why this repo does **not** do
that; it would have looked like a fix and changed nothing.

The fix is in `hypr/config/lib.lua` instead: `L.app()` wraps a command in
`uwsm app --`, giving it its own scope under `app.slice`
(`app-Hyprland-firefox-<hash>.scope`). `hypr/config/binds.lua` uses it for the
four memory-hungry launches — terminal, file manager, Firefox, and the rofi
launcher (that last one matters because apps started *from* rofi inherit
rofi's cgroup). The ~32 script and menu binds are deliberately left alone: they
use almost no memory, and a shell script in its own scope can see a different
environment than one inheriting the session's — a real risk for the ones
calling `hyprctl` and `notify-send`.

## Installing

```sh
# 1. the oomd drop-in (takes effect immediately, no reboot)
sudo install -Dm644 oomd/90-no-swap-kill.conf \
    /etc/systemd/system/user-.slice.d/90-no-swap-kill.conf
sudo systemctl daemon-reload
sudo systemctl restart systemd-oomd

# 2. disk swap
sudo ./swap/setup-swapfile.sh            # 8 GiB, or --size 16G

# 3. the cgroup split -- reload Hyprland, then log out and back in
hyprctl reload
```

`install.sh` stage 8 offers all of this.

## Checking it worked

```sh
systemctl show user-1000.slice -p ManagedOOMSwap     # ManagedOOMSwap=auto
swapon --show                                        # zram0 pri 100 + swapfile pri 10
pgrep -x firefox | xargs -I{} cat /proc/{}/cgroup    # app.slice/app-Hyprland-firefox-*.scope
```

The third one is the one that matters. If Firefox still reports
`wayland-wm@hyprland.desktop.service`, it was started from something that was
not wrapped — a rofi launcher predating this change, or an autostart entry.

## Undoing

```sh
sudo rm /etc/systemd/system/user-.slice.d/90-no-swap-kill.conf
sudo systemctl daemon-reload && sudo systemctl restart systemd-oomd
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
