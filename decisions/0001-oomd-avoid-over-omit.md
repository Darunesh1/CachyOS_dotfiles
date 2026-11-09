---
status: "accepted"
date: 2026-09-29
decision-makers: darriour
---

# Keep systemd-oomd, but move its monitoring and prefer `avoid` over `omit`

## Context and Problem Statement

systemd-oomd killed the entire Hyprland session twice while it was in use,
dropping the user to the login screen with everything open inside it:

```
Sep 28 15:04:46  systemd-oomd: Marked .../wayland-wm@hyprland.desktop.service for killing
                 due to memory used (7177072640) / total (7969300480) and
                 swap used (7503994880) / total (7969173504) being more than 90.00%
Sep 29 11:42:06  ... identical, swap used (7186481152)
```

On 8 GB with zram sized at 100% of RAM, "swap 90% full" describes a busy
laptop, not one about to wedge. The question was how to stop the compositor
being the victim without giving up early reaction to real memory pressure.

## Decision Drivers

* 8 GB of RAM with an Intel iGPU; memory pressure is normal, not exceptional.
* Losing the session loses unsaved work in every open application.
* `ManagedOOMPreference` is silently ignored unless cgroup ownership lines up.

## Considered Options

* Disable systemd-oomd entirely.
* `ManagedOOMPreference=omit` on the compositor.
* `ManagedOOMPreference=avoid` on the compositor, with monitoring moved to the
  user-owned `user@.service`.

## Decision Outcome

Chosen option: **`avoid`, with monitoring moved to `user@.service`**, plus a
disk swapfile and a cgroup split so there is something other than the desktop
to kill.

`omit` sounds stronger and is worse. It means "never a candidate", so if
something *inside* the session is the leak (waybar, swaync, awww-daemon), oomd
can take no action on the one cgroup that matters, the machine grinds, and the
kernel OOM killer then picks by `oom_score` with no notion of what a compositor
is. `omit` does not reliably save the desktop *and* forfeits the early
reaction.

Disabling oomd was rejected because memory-pressure monitoring (PSI) is the
signal worth acting on; only the swap heuristic was wrong, and that is switched
off separately with `ManagedOOMSwap=auto`.

### Consequences

* Good, because a Firefox scope dies before the compositor does.
* Good, because if the desktop genuinely is the memory hog, killing it is the
  right answer to a bug worth fixing.
* Bad, because **all three drop-ins are required** and any one alone is a no-op
  that looks like a fix. `ManagedOOMPreference` is honoured only when the
  monitored ancestor cgroup and the candidate share an owner, and CachyOS sets
  the rule on the root-owned `user-.slice`.
* Bad, because the cgroup split depends on launching apps through `uwsm app --`,
  so an app started by an unwrapped path is still in the compositor's cgroup.

### Confirmation

The only check that distinguishes a working setup from a convincing no-op:

```sh
getfattr -d -m 'user.oomd' \
  /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/session.slice/wayland-wm@hyprland.desktop.service
# -> user.oomd_avoid="1"
```

Empty output means the protection is not real, whatever the other settings say.
`./install.sh --check` runs this.

## More Information

Mechanism, the four contributing causes, the ownership quote from
`man 5 systemd.resource-control`, and the install and undo steps are in
[../system/README.md](../system/README.md).
