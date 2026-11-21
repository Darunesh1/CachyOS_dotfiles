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

The gesture state core and Lua bridge have passed deterministic tests in an isolated nested compositor. Geometry projection tests pass for one through six faces. The first nested screenshot was uniformly dark despite the Lua state reporting open, so visible rendering has **not** passed. Inactive workspace content capture and invalidation are under investigation; `content.cpp` is not yet integrated into the build. Physical touchpad behavior, 60 FPS, stress, and live activation are unverified. See [issue #22](https://github.com/Darunesh1/CachyOS_dotfiles/issues/22) for the remaining gates.
