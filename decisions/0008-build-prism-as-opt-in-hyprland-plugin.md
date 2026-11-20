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
