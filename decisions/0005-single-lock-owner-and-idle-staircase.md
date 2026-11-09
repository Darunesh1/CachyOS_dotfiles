---
status: "accepted"
date: 2026-11-09
decision-makers: darriour
---

# One lock owner, a replaceable lock screen, and the upstream idle staircase

## Context and Problem Statement

Waking the laptop showed a picture for about a second, then black, with no way
back. The power button was the only escape, which destroyed unsaved work. It
happened on every lid-close suspend for days, across at least six reboots.

Three independent faults stacked up, and one of them was introduced by an
earlier attempted fix in this repo.

## Decision Drivers

* Losing the session loses unsaved work; this is the whole point.
* The failure must be recoverable from inside the session, blind.
* A dotfiles repo should not diverge from upstream defaults without a reason.

## Considered Options

For the lock race: keep both lockers and try to serialise them; let hypridle own
locking; let the lid script own locking.

For recovery: rely on the existing panel rescue; enable
`misc:allow_session_lock_restore`; change `HandlePowerKey` so the reflex is
harmless.

For the timings: keep suspend at 330 s; adopt the upstream staircase.

## Decision Outcome

**hypridle owns locking, alone.** `lid-close.sh` ended
`pidof hyprlock >/dev/null || hyprlock &`, where `&` backgrounds the *whole*
`||` list, so the script never waited before `systemctl suspend`. logind then
ran `before_sleep_cmd = loginctl lock-session`, starting a **second** hyprlock.
hyprlock said so itself, three times:

```
onLockFinished called. Seems we got yeeten. Is another lockscreen running?
```

Upstream hypridle and the JaKooLit and HyDE dotfiles all let `lock_cmd` be the
sole owner; not one starts a locker from a lid script.

**`misc:allow_session_lock_restore = true`.** At its stock `false`, once
hyprlock died or lost its surface Hyprland refused to let a replacement attach,
so the session sat locked with nothing drawing while still swallowing
keystrokes. This is what made the black screen *permanent*.

**The upstream staircase**, because the old chain had no screen-off step at all:

| stage | upstream | JaKooLit | HyDE | was here | now |
|---|---|---|---|---|---|
| dim | 150 s | — | 60 s | absent | 150 s |
| lock | 300 s | 600 s | 120 s | 300 s | 300 s |
| DPMS off | 330 s | commented | 300 s | **absent** | 330 s |
| suspend | 1800 s | commented | 500 s | **330 s** | 1800 s |

Suspending after 5.5 minutes meant every short break was a full suspend, and
every suspend risked the faults above.

**`HandlePowerKey` is deliberately left at `poweroff`.** Pressing it in front of
a blank screen is the correct response to a dead session, not a mistake to
engineer around. Fixing recoverability is the right layer.

**`inhibit_sleep` was investigated and deliberately not changed.** HyDE forces
`3` to dodge a lock/suspend race, which resembled this one. From hypridle's
`src/core/Hypridle.cpp`, the default `2` (auto) already resolves to
`SLEEP_INHIBIT_LOCK_NOTIFY` when the lock notifier exists and `lock_cmd`
contains `hyprlock` while `before_sleep_cmd` contains `lock-session` — all true
here, `hyprland_lock_notifier_v1` is advertised, and the daemon confirms it:
`Sleep inhibition enabled - inhibiting until the wayland session gets locked`.

### Consequences

* Good, because `SUPER + SHIFT + L` (bound `locked = true`) can now replace a
  wedged lock screen, which is what the power button was being used for.
* Good, because idle no longer suspends the machine in 5.5 minutes.
* Bad, because the lid is still handled twice — logind's `HandleLidSwitch` is
  `suspend` as well — so `lid-close.sh`'s external-display logic can be
  overridden. Changing it needs root and was postponed so it is clear which fix
  did the work.
* Bad, because a reload-based panel rescue cannot help a black screen whose
  output Hyprland still believes is enabled.

### Confirmation

```sh
hyprctl getoption misc:allow_session_lock_restore   # bool: true, set: true
grep -c yeeten ~/.local/state/hypr/hyprlock.log     # must not grow
hyprctl binds -j | jq '.[] | select(.key=="L")'     # modmask 65 -> locked: true
```

## More Information

[../hypr/README.md](../hypr/README.md) carries the full evidence, including the
`dpms` argument trap described in
[0004](0004-brightness-zero-with-wake-floor.md)'s consequences. Commits
`e75ea32`, `059b809`, `230018d`.
