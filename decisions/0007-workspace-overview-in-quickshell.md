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

## Update, 2026-11-16: it became a glass cube

This does not change the decision (a Quickshell client, not a plugin); it records what
building the motion taught. The first version was a flat scrolling row that jumped
and appeared suddenly. It is now a closed prism of glass faces that rises from the
bottom of the screen, turns on a spring, and unfolds into a flat row while a window is
dragged. Full design, measurements and traps are in
[../hypr/README.md](../hypr/README.md).

Consequences worth keeping here because they bear on the decision:

* The separate-process choice was **vindicated twice** in one afternoon. A depth-range
  bug clipped every side face to a sliver, and an alpha-buffer bug leaked the desktop
  through the overlay. Both were found, diagnosed and fixed by killing and relaunching
  the overlay, with the session untouched. In a compositor plugin either would have been
  a crash-and-lose-everything iteration loop.
* Final measurements on the 8 GB Intel-iGPU laptop: first motion 196 ms after launch;
  0 percent CPU at rest and no frames drawn while idle; 17 percent CPU while a scroll
  runs (14-15 percent is the floor for animating any full-screen layer at 60 fps); RSS
  171-186 MiB while open; the overview's own render work is about 0 ms per frame.
* The wallpaper is painted by the overlay, not blurred by the compositor, so no
  full-screen blur pass runs per frame and no window text bleeds through.
* Bad, because the overlay must be an **opaque window from creation**, so it cannot
  crossfade itself and relies on Hyprland's own `layersIn` / `layersOut` fade. Changing
  those in `config/animations.lua` changes how the overview appears and disappears.

## Update, 2026-11-16 (later): it follows the swipe, and it can be resident

The cube was changed from "appears when the swipe ends" to "follows the fingers": your
current screen shrinks into the middle at the speed of the swipe and becomes the cube,
and the chosen workspace grows back out to fill the screen. That forced one cost this
record did not plan for, and one new decision.

* **Decision: a resident, hidden instance.** A gesture function runs once, when the swipe
  ends; `hl.gesture` also takes `start` / `update` / `finish` callbacks. Following the
  fingers needs the overlay already running, because starting one takes ~200 ms and a
  swipe lasts ~250-400 ms. The callbacks write one line per event to a tmpfs file that
  the overlay reads with `tail -F` (0.65 ms median). Spawning a process per event and a
  FIFO were both rejected (a process per event costs most of a core; opening a FIFO for
  writing hangs the compositor until a reader exists).
* **Bad, measured:** a hidden resident instance is ~236 MiB RSS, of which ~137 MiB is
  anonymous. My estimate beforehand was 110-170 MiB. It is a standing cost on an 8 GB
  machine where systemd-oomd killed the session twice (ADR 0001).
* **So there are two tiers.** `lite` (Game Mode on, or MemAvailable low) has no resident
  instance: it starts on demand and cannot follow the first ~200 ms of a swipe. The
  marks (1.0 GiB to drop, 1.6 GiB to return) are a first guess, not a measurement.
  Details and the measurements are in [../hypr/README.md](../hypr/README.md).
* **The separate-process choice again paid for itself:** a `kill -9` while open left
  Hyprland on the same PID with every window and the focused workspace intact, and a
  frozen overview is force-closed in about 1.4 s.

## More Information

[../hypr/README.md](../hypr/README.md) documents usage. Sources: PR
[hyprwm/Hyprland#15898](https://github.com/hyprwm/Hyprland/pull/15898),
[raybbian/hyprtasking](https://github.com/raybbian/hyprtasking), and
`hyprtester/test.lua` in Hyprland for the `hl.gesture` function form.
