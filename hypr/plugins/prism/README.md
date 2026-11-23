# Prism V3 native plugin prototype

Prism V3 is an opt-in C++ plugin experiment for the installed Hyprland 0.57.2 ABI. The choice and crash tradeoff are in [ADR 0008](../../../decisions/0008-build-prism-as-opt-in-hyprland-plugin.md). The current Quickshell Prism remains the active fallback; this plugin is not loaded by the live configuration.

## Build and test

From the repository root:

```sh
make -C hypr/plugins/prism
c++ -std=c++23 -O2 -Wall -Wextra -Wconversion -Wsign-conversion -Werror hypr/plugins/prism/core.cpp hypr/plugins/prism/tests/core_test.cpp -o /tmp/prism-core-test
/tmp/prism-core-test
c++ -std=c++26 hypr/plugins/prism/tests/render_test.cpp -o /tmp/prism-render-test
/tmp/prism-render-test
hypr/plugins/prism/tests/nested.sh --check
hypr/plugins/prism/tests/nested.sh --gesture hypr/plugins/prism/build/prism.so
```

The nested script requires an accessible parent Wayland socket, render node, and Bubblewrap. It hides host input and KMS devices, checks its child PID and Hyprland instance signature before IPC, and compares the plugin's embedded ABI before loading. `--lifecycle --cycles 100` repeats load/unload on the same isolated child. Do not use `hyprctl plugin load` against the live compositor as a substitute.

## Current limits

The gesture state core, Lua bridge, geometry and ten load/unload cycles pass in an isolated nested compositor. **Visible rendering now passes for one face** (placeholder pane, nested screenshot has 309 colours instead of one). Two bugs had made it fail, both measured with the render counters:

1. `-fvisibility=hidden` gave the plugin its own null copy of Hyprland's `inline` globals (`g_pSessionLockManager`, `g_pHyprRenderer`), so every render hook saw a "locked session" (`lockedContext == stage`). The Makefile no longer sets it; `-fno-gnu-unique` stays so unload works.
2. `g_pHyprRenderer->glBackend().lock()` aborts the compositor ("tried to lock a CWeakPointer over a CUniquePointer"): `glBackend()` is a weak pointer over Hyprland's unique pointer. Use `valid()` and `->` only. This crash is exactly why nothing may be loaded live untested.

Still open: real workspace content on the faces (`content.cpp` is compiled but not wired in), invalidation, keyboard switching, cancel, lock/unplug cleanup, 60 FPS, stress, physical touchpad, and live activation. See [issue #22](https://github.com/Darunesh1/CachyOS_dotfiles/issues/22).
