---
status: "accepted"
date: 2026-11-20
decision-makers: darriour
---

# Build Prism V3 as an opt-in Hyprland plugin

## Context and Problem Statement

Prism's Quickshell client cannot provide the requested compositor-native, finger-synchronous workspace transformation without its resident process and screen captures. The user requested a native C++ implementation while preserving Quickshell as a fallback. This changes the choice recorded in [ADR 0007](0007-workspace-overview-in-quickshell.md).

## Decision Drivers

* Direct gesture-to-render response and continuous perspective motion.
* Correct workspace identity and preview invalidation.
* Compositor stability on an 8 GB Intel iGPU laptop.
* Hyprland's plugin ABI changes across releases.

## Considered Options

* Continue the Quickshell client.
* Use an existing Hyprland overview plugin.
* Build Prism V3 as a version-pinned native plugin.

## Decision Outcome

Build a modular, version-pinned C++ plugin, initially opt-in. Keep the Quickshell implementation available until the native plugin passes nested lifecycle, gesture, rendering, and stress tests, followed by physical touchpad validation. Do not load an untested build into the live compositor.

The installed Hyprland 0.57.2 headers expose Lua function registration and render events, but whole-workspace rendering is protected. The first rendering gate must establish a supported way to compose workspace faces; no private renderer entry point is assumed.

### Consequences

* Gesture callbacks can call the plugin directly, avoiding per-event file transport and the resident Quickshell process when V3 is selected.
* A plugin crash can end the compositor session and lose unsaved work. Nested testing and explicit live activation are mandatory.
* Every Hyprland ABI change requires a rebuild and a compatibility check before loading.
* Quickshell remains the recovery path and retains its own unresolved touchpad verification issue.

### Confirmation

Build against the installed Hyprland ABI, verify load/unload in an isolated nested instance, replay gestures, check workspace content and identity, measure frame pacing and memory, and run the repository audit. Physical touchpad feel requires the user.

## Update 2026-11-23: what building it showed

The native plugin now renders real workspace content in perspective, is driven by the swipe through `hypr/config/prism_native.lua`, and passes nested lifecycle, driver, safety (including unload while open) and a 100-cycle stress run with no memory growth. Details and the measured numbers are in [the plugin README](../hypr/plugins/prism/README.md).

* Whole-workspace rendering did not need private renderer entry points: `content.cpp` draws each workspace's mapped windows and subsurfaces into its own framebuffer, outside the render pass.
* It stays **opt-in** (flag file) with the Quickshell Prism as the fallback. Not yet verified: physical touchpad feel, real-iGPU frame times, session lock and monitor unplug while open. Activation in the live compositor is the user's decision.
* Two crashes and one silent failure came from the build setup, not the design (hidden visibility nulled Hyprland's globals; locking a weak-over-unique pointer aborts; a Wayland-backend nested test stalled whenever the host hid its window). That is the argument for keeping nested testing mandatory.

## Update 2026-11-23 (live trial)

First live trial: the plugin loads and works, but the cube could not be turned with the fingers and the faces looked small.

* **Finger spin.** The core already had a horizontal turn; nothing fed it, and the three-finger horizontal swipe was still Hyprland's workspace swipe. The plugin now listens to Hyprland's cancellable `gesture.swipe.{begin,update,end}` events and owns a three-finger swipe from its first event to its last while the cube is fully open. The alternatives were a four-finger Lua gesture (no C++ risk, but a new gesture to learn and the real workspace still moves behind the cube) and leaving it as it was. Downside accepted: input handling now lives inside the compositor, and only a live trial can prove the cancel behaviour.
* **Size.** The front face was a fixed 50 %; it now adapts to the workspace count (72 % down to 58 %).

## Update 2026-11-24 (second live trial)

The plugin works and the swipe turns the cube, but it looked flat and unreadable, clicking and scrolling did nothing, and it had not loaded at login.

* **Login load.** `hl.plugin.load` called from Lua after the config has been read returns nil and loads nothing (reproduced in `nested.sh --autoload`). The loader now starts `hyprctl plugin load` as a child process, retries, and reports the reason. Alternative rejected: calling `hl.plugin.load` while the config is still being evaluated, which puts a plugin load inside config evaluation (a bad plugin could then break the config).
* **Look.** Wallpaper backdrop with a dark gradient, sharper pictures (0.75 instead of 0.4 of the screen), shadows, outline, labels. Rounded corners were not done: the compositor's textured-mesh path rounds a box, not a perspective quad.
* **Pointer.** Click and scroll are routed by a pure, tested router; press and release are cancelled as a pair because Hyprland drops a cancelled press from its bookkeeping.
* **Power.** Two tiers, full and lite, chosen from two flag files. Alternative rejected: running `powerprofilesctl get` when the cube opens (a process spawn inside the compositor's callback).
* **Window drag (stage 2).** With three or four workspaces the cube shows only its front face (the others are edge-on or facing away), so nothing would be left to drop a window on. While a window is dragged the cube therefore unfolds into a flat row of every workspace (`flatness` in the core, a spring like the others). Alternatives rejected: a separate strip overlay (a second layout to build and keep in step) and dropping only on the visible side faces (works from five workspaces up). The window is moved by Hyprland's own dispatcher from Lua rather than by plugin code reaching into the compositor.

