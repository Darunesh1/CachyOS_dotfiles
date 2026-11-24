# Prism V3 native plugin prototype

Prism V3 is an opt-in C++ plugin experiment for the installed Hyprland 0.57.2 ABI. The choice and crash tradeoff are in [ADR 0008](../../../decisions/0008-build-prism-as-opt-in-hyprland-plugin.md). The current Quickshell Prism remains the active fallback; this plugin is not loaded by the live configuration.

## Build and test

From the repository root:

```sh
make -C hypr/plugins/prism
c++ -std=c++23 -O2 -Wall -Wextra -Wconversion -Wsign-conversion -Werror hypr/plugins/prism/core.cpp hypr/plugins/prism/tests/core_test.cpp -o /tmp/prism-core-test && /tmp/prism-core-test
c++ -std=c++26 hypr/plugins/prism/tests/render_test.cpp -o /tmp/prism-render-test && /tmp/prism-render-test
c++ -std=c++23 -O2 -Wall -Wextra -Wconversion -Wsign-conversion -Werror hypr/plugins/prism/core.cpp hypr/plugins/prism/tests/swipe_test.cpp -o /tmp/prism-swipe-test && /tmp/prism-swipe-test
c++ -std=c++26 -O2 -Wall -Wextra hypr/plugins/prism/tests/hit_test.cpp -o /tmp/prism-hit-test && /tmp/prism-hit-test
c++ -std=c++26 -O2 -Wall -Wextra hypr/plugins/prism/core.cpp hypr/plugins/prism/tests/pointer_test.cpp -o /tmp/prism-pointer-test && /tmp/prism-pointer-test
hypr/plugins/prism/tests/nested.sh --autoload   # the way the config loads it at login
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

**Loading.** The config loads the plugin at login with `hyprctl plugin load` (started from Lua, retried, and a notification says why if it fails; the answer is also in `$XDG_RUNTIME_DIR/prism/load-result`). It is NOT `hl.plugin.load`: measured in `nested.sh --autoload`, that call returns nil and loads nothing once the config has been read, which is why the first live trial did not load at login. **After rebuilding**, the running compositor still has the OLD file mapped (the linker replaces the file, it does not overwrite it, so nothing crashes). Load the new one: `hyprctl plugin unload ~/.config/hypr/plugins/prism/build/prism.so`, then `hyprctl plugin load ~/.config/hypr/plugins/prism/build/prism.so` (cube closed; unload while open is tested but pointless).

## How it looks and what you can do (2026-11-24)

| | |
|---|---|
| Backdrop | your wallpaper (`~/Pictures/Wallpaper/current_wallpaper`, any size, shrunk to 1920 wide, cover-fit) under a dark gradient; the same wallpaper behind each face, so an empty workspace looks like a desktop. Reloaded when the file changes |
| Faces | a soft three-ring shadow, a 2 px outline (accent `#8ab4f8` on the workspace you are on), a label pill under each: `2 · 3 windows` / `empty`, accent when current |
| Sharpness | pictures captured at 0.75 of the screen (long side at most 1600 px); lite uses 0.4 |
| Click | a side face turns to the front; the front face goes to that workspace; the backdrop closes without changing workspace; press and release are swallowed as a pair so the app underneath never sees half a click |
| Drag a window | press on a window in the cube and move: the cube unfolds into a flat row of every workspace (so each is a drop target even with only 3 or 4, when a cube shows just its front face); the window follows the cursor as a translucent thumbnail, the workspace under it gets a thick accent outline; release on another workspace moves the window there **silently** (you stay on your workspace, the cube folds back and stays open); release on its own workspace or the backdrop, or press Escape, cancels. The move itself is `hl.dsp.window.move({ ..., follow = false })`, done by the Lua watcher |
| Scroll | wheel or two-finger scroll turns one face per step (touchpad needs about 40 units, at most one face per 120 ms) |
| Swipe | 3 fingers up opens, sideways turns, down closes (see above) |
| Keys | arrows, Enter, Esc |

**Power tiers** (`hl.plugin.prism.setQuality`, chosen in `prism_native.lua` when the cube opens): **full** (wallpaper, shadows, 0.75 pictures) in Balanced and Performance; **lite** (plain gradient, no shadows, 0.4 pictures, the wallpaper texture freed) in Power Saving and in Game Mode. The signal is two files: `$XDG_RUNTIME_DIR/game-mode/active` (Game Mode, existing) and `$XDG_RUNTIME_DIR/prism/power-saver` (written by `hypr/scripts/power/hypr-profile.sh`). Downside: a profile changed by anything else is not seen, and the flag is gone after a reboot while power-profiles-daemon may still be in power-saver (the audit row "prism power tier" warns about that).

**Not done / not verified:** rounded corners (the compositor's mesh path cannot round a perspective quad; the outline and shadow carry the look instead); workspace names (Hyprland keeps them private, so the number is shown); real clicks, scrolls, drags and touchpad feel. Drag picks the window from the picture taken at open (window positions are recorded at capture), so a window that moved since is picked by its old place until the next capture; with more than 8 workspaces the faces of the flat row get very small. The nested test cannot make the compositor deliver pointer events, so `hl.plugin.prism.pointerClick/pointerScroll/pointerPress/pointerMove/pointerRelease` drive the same routers from Lua (the nested test really drags a window to another workspace and reads the window counts back) (that proves the logic, not Hyprland's event path); `renderDiagnostics().clicksOwned` and `swipesOwned` count what the live listeners took. `./install.sh --check` has a "prism native plugin" row: it says "off", or warns when you are opted in but the build is missing or was made for another Hyprland (rebuild after every Hyprland update; a mismatched plugin refuses to load and Quickshell takes over).

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
