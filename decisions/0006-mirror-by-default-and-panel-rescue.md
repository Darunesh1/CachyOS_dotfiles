---
status: "accepted"
date: 2026-10-15
decision-makers: darriour
---

# External displays mirror by default, and a dark panel is rescued by reloading

## Context and Problem Statement

Two related problems. First, what should happen when a display is plugged in.
Second, "External screen only" switches `eDP-1` off, so unplugging the cable
then leaves zero enabled outputs — Hyprland creates a headless placeholder
called `FALLBACK` so the session survives, but headless shows nothing and the
machine is simply dark, with no screen on which to fix it.

## Decision Drivers

* The laptop panel must never be the only thing switched off with no way back.
* A rescue that loops is worse than a dark screen.
* `hyprctl reload` is one of very few actions that work blind.

## Considered Options

For plug-in behaviour: extend, mirror, or ask each time.

For the rescue: an `hl.monitor` eval to re-enable the panel directly; a
`hyprctl reload`; nothing, and rely on a keybind the user remembers.

## Decision Outcome

**Mirror by default**, via a catch-all rule with an empty `output` so it covers
whichever monitor appears. The chosen mode is stored in
`hypr/config/display-mode.lua`, and "External screen only" is deliberately
**not representable** there — it stores the external geometry only, and the
panel being off is applied live and never written, so a reload or a reboot
always comes back with a lit screen.

**Rescue by reloading, not by evaluating `hl.monitor`.**
`CMonitorFrameScheduler::canRender()` is false while a monitor is disabled, so
an `hl.monitor` eval issued when nothing is rendering can be queued and never
applied. A reload re-reads the config from disk, and is safe precisely because
the `eDP-1` rule spells out `disabled = false` while the catch-all is read from
the stored mode — the panel comes back and the user's choice survives.

The rescue is guarded by a three-strike counter in a deliberate `_G` global.
Measured: `hyprctl reload` **clears all `hl.on` subscriptions**, so handlers do
not accumulate and registration must **not** be guarded by a flag — a `_G`
guard would survive the reload that cleared the subscription and permanently
block re-registration, silently killing the rescue after the first reload. The
counter itself must be global for the opposite reason: a `local` would reset on
the very reload it needs to count.

### Consequences

* Good, because plugging in a display never blanks anything, and unplugging
  cannot leave the session with no visible output.
* Good, because the guard makes a reload loop impossible: three reloads in 30 s
  that do not produce a lit screen stop trying.
* Bad, because a mirror runs the external at the panel's resolution. Extending
  is a deliberate choice in the display menu, not the default.
* Bad, because the rescue is registered only on `monitor.removed` and
  `config.reloaded`. A wake from suspend fires neither, and Hyprland exposes no
  resume event to Lua, so the resume case needs a separate trigger from
  hypridle's `after_sleep_cmd` — see
  [0005](0005-single-lock-owner-and-idle-staircase.md).
* Bad, because it cannot help a dark screen whose output Hyprland still believes
  is enabled; `lit_screens()` returns 1 and it exits.

### Confirmation

```sh
hyprctl monitors -j | jq '[.[] | select(.name != "FALLBACK")] | length'   # lit outputs
```

`FALLBACK` is excluded by name in both the Lua guard and the shell scripts:
counting it would make the guard believe there is a screen to look at.

## More Information

[../hypr/README.md](../hypr/README.md) and the comments in
`../hypr/config/monitors.lua`, which carry the measured API behaviour. Commit
`dddf95e`.
