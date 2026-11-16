---
status: "accepted"
date: 2026-11-16
decision-makers: darriour
---

# Build the workspace overview as a Quickshell client, not a Hyprland plugin

## Context and Problem Statement

The user wanted a three-finger swipe up to show every workspace as a
translucent card with its windows on it, scrollable, with windows draggable
between workspaces. Hyprland 0.57.2 has no overview of its own.

## Decision Drivers

* The user has lost unsaved work repeatedly to compositor-level failures, so new
  code must not sit on the path that can take the compositor down.
* 8 GB of RAM; nothing should be resident when it is not being looked at.
* Hyprland releases every two to three months, so anything coupled to its ABI
  breaks on a schedule.

## Considered Options

* **A.** The `hyprtasking` plugin, built with `hyprpm`.
* **B.** A custom Quickshell overview, started on demand.
* **C.** Bind the gesture to the existing rofi window switcher.
* **D.** Wait for Hyprland's native overview.

## Decision Outcome

Chosen option: **B**, with the gesture one line in `hypr/config/input.lua` so it
can be repointed at the native overview later.

**Why not A.** `hyprtasking` has everything wanted, but it runs inside the
compositor, so a crash there kills every open app and loses unsaved work. On
top of that:

* its README says `Supports Hyprland releases v0.46.2-v0.57.0` and this machine
  runs 0.57.2;
* issue #141 "Compile failed with Hyprland 0.57" is open, and #93 "Random
  crashes, dead images and program outside grid" has been open since March;
* its `hyprpm.toml` builds with `meson setup build --buildtype=debug`;
* its default open gesture is four fingers, not three;
* plugins must match the compositor ABI exactly, so it is rebuilt after every
  Hyprland update.

**Why not D.** Hyprland's own overview is PR #15898 "overview: add overview":
open, `REVIEW_REQUIRED`, 9,023 additions across 221 files, last updated Nov 8.
Its prerequisites merged in 0.57.0 (input redirecting #16141, scene composition
#16340, pointer transforms #16143), but there is no release date, and releases
have come two to three months apart. `strings /usr/bin/Hyprland` shows no
overview code in 0.57.2. When it ships, switching is one line.

**Why not C.** It is a list, not a grid, with no live pictures and no drag to
rearrange. It stays on `SUPER + Tab`.

`hyprexpo` is no longer an option: it was removed from `hyprland-plugins`, whose
plugin list is now `borders-plus-plus`, `csgo-vulkan-fix`, `hyprbars`,
`hyprfocus`. Its last commit was 2026-01-01.

### Consequences

* Good, because it is an ordinary Wayland client. Measured: killing it with
  `kill -9` while it was open left Hyprland on the same PID with all five
  windows intact and no overlay layer left behind.
* Good, because it is started on demand and exits when closed, so it costs
  nothing at rest. Measured while open: 161 MiB resident, 140 MiB proportional.
* Good, because it uses stable Wayland protocols and `hyprctl`, so a Hyprland
  update cannot break it the way an ABI-coupled plugin can.
* Bad, because the QML is ours to maintain, about 300 lines.
* Bad, because it is a second moving part: `quickshell` must be installed, and
  the first paint has a short cold start while the process launches.
* Bad, because Quickshell's own Hyprland module is unusable for workspace
  identity on 0.57 (below), so the data path is hand-rolled.

### Two traps found while building it

**Quickshell 0.3.2 reports `HyprlandWorkspace.id = -1` for every workspace**, and
every window's workspace id is `-1` too, on Hyprland 0.57.2. Names are correct,
ids are not. So workspace and window layout come from `hyprctl ... -j`, whose ids
are right, and Quickshell is used only for `ScreencopyView`, the live window
pictures. `HyprlandToplevel.address` also lacks the `0x` prefix that `hyprctl`
prints, so addresses are compared with the prefix stripped.

**A window move follows the window by default.** Dropping a test window on
workspace 5 took the focus from 1 to 5, which would strand the user somewhere
unasked once the overview closed. `hl.dsp.window.move({ workspace = N, follow =
false, window = "address:0x..." })` is the silent form. Read from Hyprland's
`hlWindowMove` (`silent = follow.has_value() && !*follow`) and confirmed by read
back: the test window moved to workspace 3 and the focus stayed on 5. As with
`dpms`, `hyprctl dispatch` printing `ok` proved nothing; every claim here was
checked by reading `hyprctl clients -j` back.

### Confirmation

```sh
./install.sh --check                       # the `workspace overview` row
hypr/scripts/overview/toggle.sh toggle     # opens it; again closes it
qs list -c overview -j | jq length         # 1 while open, 0 after
```

## More Information

[../hypr/README.md](../hypr/README.md) documents usage. Sources: PR
[hyprwm/Hyprland#15898](https://github.com/hyprwm/Hyprland/pull/15898),
[raybbian/hyprtasking](https://github.com/raybbian/hyprtasking), and
`hyprtester/test.lua` in Hyprland for the `hl.gesture` function form.
