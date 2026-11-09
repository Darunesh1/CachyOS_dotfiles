---
status: "accepted"
date: 2026-11-07
decision-makers: darriour
---

# Let the brightness key reach zero, and restore a 5% floor on wake

## Context and Problem Statement

The Fn brightness-down key bottomed out well above black. The cause was not in
this repo: the packaged `/etc/xdg/swayosd/config.toml` ships
`min_brightness = 5`, which pinned `intel_backlight` at 4800 of 96000 —
exactly 5%, which is where it was found sitting. The user wanted the key to
reach a genuinely black screen.

## Decision Drivers

* A black screen is wanted deliberately, in a dark room.
* A machine suspended at 0 must not wake to an unusable panel.
* The system config file is owned by a package.

## Considered Options

* Edit `/etc/xdg/swayosd/config.toml` in place.
* A local `~/.config/swayosd/config.toml` override with `min_brightness = 0`.
* Keep the 5% floor on the key and add a separate bind that jumps to zero.
* Dim below the hardware floor in software, with gamma or a shader.

## Decision Outcome

Chosen option: **a local override setting `min_brightness = 0`, plus a 5% floor
restored on wake.**

Editing the system file was rejected: `pacman -Qi swayosd` reports
`Backup Files : None`, so it is not a pacman backup file and any local change is
silently discarded on the next upgrade.

A separate zero bind was the user's first preference and was then overridden by
the user, who wanted the existing Fn key to walk all the way down.

Software gamma dimming was rejected: it is a separate mechanism from the
brightness keys, costs GPU work on an Intel iGPU, and washes out colour rather
than dimming.

Read out of SwayOSD's `src/actions/brightness_backend/brightnessctl.rs` rather
than guessed: `min` is a **percentage** scaled to a raw floor with
`min_raw = div_round_u32(min * max, 100)`, `lower` is
`curr.saturating_sub(step).max(min_raw)`, and `raise` from `curr = 0` is
`(0 + step).min(max).max(min_raw)` = `step`. So zero is reachable and is **not**
a trap.

Note the user config **replaces** the system one rather than merging —
`find_user_config()` returns the first file it finds — so settings worth keeping
must be repeated in it.

### Consequences

* Good, because the key reaches raw 0, and brightness-up escapes it.
* Bad, because the step is 5% of max, so there is no finer control near black:
  one press from 5% goes straight to 0. The waybar backlight module moves 1% at
  a time and was never subject to the floor.
* Bad, because the brightness keys carry `locked = true`, so the backlight can
  now be switched fully off at the lock screen. This made a later black-screen
  fault harder to recover from. See [0005](0005-single-lock-owner-and-idle-staircase.md).

### Confirmation

```sh
cat /sys/class/backlight/intel_backlight/brightness   # 0 after holding Fn-down
~/.config/hypr/scripts/display/brightness-floor.sh    # 0 -> 4800, no-op above
```

Measured: lower from 4800 goes straight to 0; one raise returns 4800. The floor
script is a no-op at 4800 and at 38400, and raises only.
`./install.sh --check` carries `brightness floor` and
`brightness reset on wake` rows.

## More Information

[../hypr/README.md](../hypr/README.md). Commit `e75ea32`.
