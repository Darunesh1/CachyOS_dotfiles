# Prism V3 native plugin prototype

Prism V3 is an opt-in C++ plugin experiment for the installed Hyprland 0.57.2 ABI. The choice and crash tradeoff are in [ADR 0008](../../../decisions/0008-build-prism-as-opt-in-hyprland-plugin.md). The current Quickshell Prism remains the active fallback; this plugin is not loaded by the live configuration.

## Build and test

From the repository root:

```sh
make -C hypr/plugins/prism
c++ -std=c++23 -O2 -Wall -Wextra -Wconversion -Wsign-conversion -Werror hypr/plugins/prism/core.cpp hypr/plugins/prism/tests/core_test.cpp -o /tmp/prism-core-test && /tmp/prism-core-test
c++ -std=c++26 hypr/plugins/prism/tests/render_test.cpp -o /tmp/prism-render-test && /tmp/prism-render-test
c++ -std=c++23 -O2 -Wall -Wextra -Wconversion -Wsign-conversion -Werror hypr/plugins/prism/core.cpp hypr/plugins/prism/tests/swipe_test.cpp -o /tmp/prism-swipe-test && /tmp/prism-swipe-test
hypr/plugins/prism/tests/nested.sh --check
hypr/plugins/prism/tests/nested.sh --lifecycle --cycles 20
hypr/plugins/prism/tests/nested.sh --gesture
hypr/plugins/prism/tests/nested.sh --driver      # the Lua driver the real config uses
hypr/plugins/prism/tests/nested.sh --safety      # abuse while open
hypr/plugins/prism/tests/nested.sh --stress      # 100 real-time cycles, memory and timing
hypr/plugins/prism/tests/nested.sh --screenshot /tmp/prism.png --windows
```

`nested.sh` needs Bubblewrap, a render node, `grim` and Python with Pillow (screenshot gate). It runs a Hyprland in an isolated sandbox, **renders on a headless output** and switches the host-window output off. (With the Wayland backend the nested compositor only drew while the host showed its window; it landed on another host workspace and every animation looked hung. That cost a day of suspicion of the plugin.) Do not use `hyprctl plugin load` against the live compositor as a substitute.

## Turning it on (opt-in)

The plugin runs **inside the compositor**: a crash in it ends the session. Save your work first.

```sh
make -C ~/MyArch/hypr/plugins/prism
touch ~/.config/hypr/prism-native     # then SUPER + SHIFT + R to reload
rm    ~/.config/hypr/prism-native     # back to the Quickshell Prism
```

`hypr/config/prism_native.lua` loads it a moment after the config, takes the 3-finger swipe, and gives you Left/Right (turn), Return (choose), Escape (cancel) while the cube is open. **SUPER + SHIFT + O** is the kill switch.

**Turning the cube with your fingers.** While the cube is fully open, a three-finger swipe is owned by the plugin (`swipe.hpp`, listeners in `plugin.cpp`): sideways turns the cube and snaps to a face, down closes it onto the front face, up does nothing. It listens to Hyprland's swipe events and cancels every event of such a swipe, so Hyprland's own workspace swipe does not also run. When the cube is closed, opening or closing, or the swipe has another finger count, the swipe is not touched. `hl.plugin.prism.renderDiagnostics().swipesOwned` counts the swipes taken: if it stays 0 after you swiped on an open cube, the events never reached the plugin. **Not verified:** the nested test cannot inject touchpad swipes, so the cancel behaviour itself is only proven by a live trial; the routing logic is unit-tested (`tests/swipe_test.cpp`, and it fails when the ownership rule is removed).

**Face size** adapts to the number of workspaces (`openFaceFraction` in `render.hpp`): the open front face fills about 72 % of the screen with 2 workspaces, 68 % with 3, 65 % with 4, 61 % with 5 and 58 % with 6 or more, always in the screen's own shape. Downside: the size changes when a workspace opens or closes. The numbers are a first guess to be tuned by eye. With 3 or 4 workspaces the neighbours are edge-on or facing away (the sides of a cube), as they were at the old fixed 50 %, so only the front face shows until it turns; from 5 workspaces the two neighbours show beside it.

**After rebuilding**, reload the config (SUPER + SHIFT + R): the plugin is loaded again from the new file. Do not rebuild while the plugin is loaded if you can avoid it. `./install.sh --check` has a "prism native plugin" row: it says "off", or warns when you are opted in but the build is missing or was made for another Hyprland (rebuild after every Hyprland update; a mismatched plugin refuses to load and Quickshell takes over).

## What was measured (nested, headless, 2026-11-23)

| gate | result |
|---|---|
| faces show real window content | red/green/blue windows on workspaces 1 to 3; screenshot has them on the faces (colour gate) |
| front face is never stale | the starting workspace is re-captured at every open; others are reused for 2 s unless a window event invalidated them |
| turn then Enter at once | chooses the face being turned to (unit test, fails without the fix) |
| driver | swipe, keys submap, rotate, close lands on the chosen workspace, reset |
| safety | new window while open, workspace leaves the list, reset mid-animation, 40 fast cycles, unload while open: all pass, repeated |
| stress | 100 cycles, 5050 frames, hook mean 17 us and max 3.4 ms, capture max 3.9 ms, 0 failures |
| idle cost | counters unchanged for 3 s while closed |
| memory | no growth after warm-up |

Timings are the plugin's CPU time per frame, **not GPU time**, and the nested compositor is software-rendered: they show there is no leak or stall, not that it is smooth on your iGPU.

## Not verified

- **Physical touchpad feel and 60 FPS on the real iGPU.** Only a live trial can say.
- **Session lock and monitor unplug while open.** The code resets the overview and drops its pictures, but the nested instance has one output and no lock screen, so neither path has been exercised.
- **A plugin built for another Hyprland**: the audit row's mismatch branch is written but untested (the matching and not-built branches were tested).
- Pictures of a hidden workspace can be up to 2 s old if a client repaints without any window event.

## Traps found

1. `-fvisibility=hidden` gives the plugin its own null copy of Hyprland's `inline` globals (`g_pSessionLockManager`, `g_pHyprRenderer`); every render hook then saw a locked session. Do not set it. `-fno-gnu-unique` stays so unload works.
2. `g_pHyprRenderer->glBackend().lock()` aborts the compositor: it is a weak pointer over a unique pointer. Use `valid()` and `->`.
3. `monitor.layoutChanged` also fires when a window opens; resetting on it closed the cube under the user's hands.
4. Capture (`content.cpp`) cannot run inside the render pass; it runs from the Lua callbacks (`begin`, `open`).

See [issue #22](https://github.com/Darunesh1/CachyOS_dotfiles/issues/22) and [ADR 0008](../../../decisions/0008-build-prism-as-opt-in-hyprland-plugin.md).
