#!/usr/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: nested.sh --check
       nested.sh --lifecycle [--cycles COUNT] [PLUGIN]
       nested.sh --gesture [PLUGIN]
       nested.sh --screenshot OUTPUT [--windows] [PLUGIN]
       nested.sh --driver [PLUGIN]
       nested.sh --safety [PLUGIN]
       nested.sh --stress [PLUGIN]
       nested.sh --autoload [PLUGIN]

--check       Start an isolated Hyprland and verify its Wayland output.
--lifecycle   Verify Prism load and unload on the same isolated instance.
--gesture     Drive Prism's Lua callbacks and verify state before unloading.
--screenshot  Open Prism and save a PNG of the nested output before unloading.
--driver      Open three windows, then drive Prism through hypr/config/prism_native.lua
              (swipe callbacks, keys submap, watcher, selection, watchdog reset).
--autoload    Load the plugin the way the config does (hl.plugin.load from the Lua driver,
              prism_native.start with its retries) instead of with hyprctl.
--stress      100 real-time open/close cycles with three windows; reports memory growth,
              idle cost while closed, frame time and capture time.
--safety      Open three windows, then abuse Prism while open: new window, workspace
              removed, reset mid-animation, 40 fast open/close cycles, unload while
              open. The nested compositor must stay alive and answer after each.
--windows     With --screenshot: first open a red, green and blue window on workspaces
              1, 2 and 3, so each face has distinct content.
COUNT         1 to 100, default 10.
PLUGIN        Path to a built shared object, default ../build/prism.so.
OUTPUT        New file under /tmp, for example /tmp/prism-preview.png.

Run from a Wayland terminal with Bubblewrap and GPU render-node access.
EOF
}

fail() {
    printf 'Prism nested test: %s\n' "$*" >&2
    exit 1
}

find_instance() {
    local instance
    instance=$(/usr/bin/hyprctl -j instances | /usr/bin/jq -er \
        --argjson pid "$child_pid" --arg wl_socket "$child_socket" '
            select(type == "array" and length == 1) | .[0]
            | select(.pid == $pid and .wl_socket == $wl_socket) | .instance
            | select(test("^[a-zA-Z0-9]+_[0-9]+_[0-9]+$"))
        ') || return 1
    local socket_path="$XDG_RUNTIME_DIR/hypr/$instance/.socket.sock"
    [[ -S $socket_path && ! -L $socket_path ]] || return 1
    [[ -S $XDG_RUNTIME_DIR/$child_socket && ! -L $XDG_RUNTIME_DIR/$child_socket ]] || return 1
    printf '%s\n' "$instance"
}

child_is_hyprland() {
    local stat parent
    [[ -n $child_pid && /proc/$child_pid/exe -ef /usr/bin/Hyprland ]] || return 1
    IFS= read -r stat <"/proc/$child_pid/stat" || return 1
    read -r _ parent _ <<<"${stat##*) }"
    [[ $parent == "$harness_pid" ]]
}

nested_ctl() {
    local instance
    child_is_hyprland || fail 'the nested Hyprland child exited or changed identity'
    instance=$(find_instance) || fail 'the nested IPC endpoint is unavailable'
    [[ $instance == "$signature" ]] || fail 'the nested instance signature changed'
    /usr/bin/hyprctl --instance "$signature" "$@"
}

expect_lua() {
    local label=$1 code=$2 expected=$3 reply
    reply=$(nested_ctl repl "$code") || fail "$label: $reply"
    [[ $reply == "$expected" ]] || fail "$label: expected $expected, got $reply"
    printf '%s: %s\n' "$label" "$reply"
}

check_plugin_abi() {
    local plugin=$1 running_abi built_abi
    [[ -x /usr/bin/readelf ]] || fail 'readelf is required to verify the plugin ABI'
    built_abi=$(/usr/bin/readelf -p .prism_abi -- "$plugin" | /usr/bin/sed -nE \
        's/^[[:blank:]]*\[[[:blank:]]*0\][[:blank:]]*([^[:blank:]]+)[[:blank:]]*$/\1/p') \
        || fail 'could not read the plugin ABI from the shared object'
    [[ -n $built_abi ]] || fail 'the plugin has no build ABI record, rebuild prism.so'

    running_abi=$(/usr/bin/Hyprland --version-json | /usr/bin/jq -er \
        '.abiHash | select(type == "string" and length > 0)') \
        || fail 'could not read the installed Hyprland ABI'
    [[ $running_abi == "$built_abi" ]] \
        || fail "plugin ABI $built_abi differs from installed Hyprland ABI $running_abi"
    printf '%s\n' "$built_abi"
}

test_gestures() {
    local code
    code=$(cat <<'LUA'
local prism = hl.plugin.prism
local function near(actual, expected)
    return math.abs(actual - expected) < 0.000001
end
local function settle(phase)
    for _ = 1, 120 do
        if not prism.snapshot().animating then break end
        assert(prism.tick(1 / 120))
    end
    local state = prism.snapshot()
    assert(not state.animating and state.phase == phase, "did not settle at " .. phase)
    return state
end

assert(prism.reset())
assert(prism.setWorkspaces({2, 11, 7}))
assert(prism.begin("up", 11))
assert(prism.update(0, -120, 0.1))
local held = prism.snapshot()
assert(held.phase == "opening" and near(held.openness, 0.4), "up swipe did not follow its first delta")
assert(held.frontWorkspace == 11 and held.originWorkspace == 11, "up swipe did not start on workspace 11")
assert(prism.tick(0.1))
assert(near(prism.snapshot().openness, held.openness), "holding the swipe changed its position")
assert(prism.update(0, 30, 0.1))
local reversed = prism.snapshot().openness
assert(near(reversed, 0.3), "the up swipe did not follow a change of direction")
assert(prism.finish(false, 0))
assert(settle("closed").openness == 0 and prism.takeSelection() == nil, "a short swipe opened Prism")

assert(prism.begin("up", 2))
assert(prism.update(0, -160, 0.12))
assert(prism.finish(false, 0))
assert(settle("open").openness == 1, "the committed up swipe did not open Prism")

assert(prism.begin("horizontal", 2))
assert(prism.update(180, 0, 0.1))
local turning = prism.snapshot()
assert(turning.openness == 1 and near(turning.facePosition, -0.6), "horizontal movement did not follow the swipe")
assert(turning.frontWorkspace == 7, "rotation did not wrap to workspace 7")
assert(prism.finish(false, 0))
assert(settle("open").frontWorkspace == 7, "rotation did not settle on workspace 7")

assert(prism.begin("horizontal", 2))
assert(prism.update(360, 0, 0.1))
assert(prism.snapshot().frontWorkspace ~= 7, "the second horizontal swipe did not turn the prism")
assert(prism.finish(true))
assert(settle("open").frontWorkspace == 7, "cancelling rotation did not restore workspace 7")

assert(prism.begin("down", 2))
assert(prism.update(0, 140, 0.12))
assert(prism.snapshot().phase == "closing", "the down swipe did not start closing Prism")
assert(prism.finish(false, 0))
assert(prism.takeSelection() == nil, "a workspace was selected before the close settled")
assert(settle("closed").openness == 0, "the committed down swipe did not close Prism")
local selected = prism.takeSelection()
assert(selected == 7 and prism.takeSelection() == nil, "close did not select workspace 7 exactly once")

return string.format("held %.2f, reversed %.2f, wrapped and selected workspace %d once", held.openness, reversed, selected)
LUA
    )
    expect_lua 'Prism gesture readback' "$code" 'held 0.40, reversed 0.30, wrapped and selected workspace 7 once'
}

# The nested compositor draws only when the HOST shows its window (a Wayland client gets
# frame callbacks only while visible). If you switch host workspace, or something covers
# the window, it stops rendering and every animation looks hung. That is the test
# environment, not the plugin, so say so instead of failing mysteriously.
require_frames() {
    local before after
    before=$(nested_ctl repl 'hl.plugin.prism.reset(); return hl.plugin.prism.renderDiagnostics().stage') || fail 'could not read the frame counter'
    /usr/bin/sleep 1
    after=$(nested_ctl repl 'return hl.plugin.prism.renderDiagnostics().stage') || fail 'could not read the frame counter'
    [[ $after -gt $before ]] || fail 'the nested compositor is not rendering frames: its window is not visible on the host (another host workspace is active, or it is covered). Keep the nested window visible and do not switch workspace while the test runs.'
}

# One solid-colour terminal per workspace, so every face has content that tells it apart.
# The clients run inside the sandbox and connect to the nested compositor, not the host.
open_test_windows() {
    local -a colors=(c01818 18a030 2040d0)
    local i count deadline
    for i in 1 2 3; do
        expect_lua "Workspace $i" "hl.dispatch(hl.dsp.focus({ workspace = $i })); return $i" "$i"
        nested_ctl dispatch "hl.dsp.exec_cmd('kitty --config NONE --override background=#${colors[i-1]} --override confirm_os_window_close=0 --override hide_window_decorations=yes sleep 600')" >/dev/null \
            || fail "could not start the test window on workspace $i"
        deadline=$((SECONDS + 25))
        while (( SECONDS < deadline )); do
            count=$(nested_ctl -j clients | /usr/bin/jq -r 'length') || fail 'could not list nested windows'
            [[ $count == "$i" ]] && break
            /usr/bin/sleep 0.2
        done
        [[ $count == "$i" ]] || fail "test window $i did not appear (clients: $count)"
    done
    # Let the first frames of the new windows reach the compositor.
    /usr/bin/sleep 1
    require_frames
    printf 'Nested windows per workspace: %s\n' \
        "$(nested_ctl -j clients | /usr/bin/jq -c '[.[] | {ws: .workspace.id, class}] | sort_by(.ws)')"
}

capture_nested() {
    local output_name=$1 code front workspaces turn
    if [[ ${PRISM_TEST_WINDOWS-0} == 1 ]]; then
        open_test_windows
        front=2
        turn=true
        workspaces='{1, 2, 3}'
    else
        front=1
        turn=false
        workspaces='{1, 2, 3, 4}'
    fi
    code=$(cat <<LUA
local prism = hl.plugin.prism
assert(prism.reset())
assert(prism.setWorkspaces($workspaces))
assert(prism.begin("up", $front))
assert(prism.update(0, -160, 0.12))
assert(prism.finish(false, 0))
for _ = 1, 120 do
    if not prism.snapshot().animating then
        break
    end
    assert(prism.tick(1 / 120))
end
local state = prism.snapshot()
assert(state.openness == 1 and not state.animating, "Prism did not finish opening")
assert(state.frontWorkspace == $front, "workspace $front is not in front")
if $turn then
    -- Hold a sideways swipe half way, so the neighbouring faces are on screen.
    assert(prism.begin("horizontal", $front))
    assert(prism.update(110, 0, 0.1))
end
return state.phase
LUA
    )
    expect_lua 'Prism before capture' "$code" open
    local counters
    counters=$(nested_ctl repl 'local d=hl.plugin.prism.renderDiagnostics(); return string.format("stage=%d noctx=%d locked=%d closed=%d attempted=%d candidates=%d ready=%d enqueued=%d drawn=%d captured=%d failed=%d reused=%d", d.stage, d.missingContext, d.lockedContext, d.closedState, d.attempted, d.candidates, d.ready, d.enqueued, d.drawn, d.captured, d.captureFailed, d.reused)') \
        || fail 'could not read Prism render diagnostics before capture'
    printf 'Prism render diagnostics before capture: %s\n' "$counters"
    WAYLAND_DISPLAY="$XDG_RUNTIME_DIR/$child_socket" \
        /usr/bin/timeout 10s /usr/bin/grim -t png -o "$output_name" - >&3 3>&- \
        || fail 'could not capture the nested output with grim'
    expect_lua 'Prism after capture' 'return hl.plugin.prism.snapshot().phase' open
    counters=$(nested_ctl repl 'local d=hl.plugin.prism.renderDiagnostics(); return string.format("stage=%d noctx=%d locked=%d closed=%d attempted=%d candidates=%d ready=%d enqueued=%d drawn=%d captured=%d failed=%d reused=%d", d.stage, d.missingContext, d.lockedContext, d.closedState, d.attempted, d.candidates, d.ready, d.enqueued, d.drawn, d.captured, d.captureFailed, d.reused)') \
        || fail 'could not read Prism render diagnostics'
    printf 'Prism render diagnostics: %s\n' "$counters"
}

wait_phase() {
    local want=$1 phase i
    for (( i = 0; i < 100; ++i )); do
        phase=$(nested_ctl repl 'return hl.plugin.prism.snapshot().phase') || fail 'could not read the Prism phase'
        [[ $phase == "$want" ]] && return 0
        /usr/bin/sleep 0.1
    done
    fail "Prism did not reach phase $want (last: $phase; $(nested_ctl repl 'local s = hl.plugin.prism.snapshot(); return string.format("openness=%.4f face=%.4f animating=%s front=%s origin=%s", s.openness, s.facePosition, tostring(s.animating), tostring(s.frontWorkspace), tostring(s.originWorkspace))' 2>&1); $(nested_ctl repl 'local d = hl.plugin.prism.renderDiagnostics(); return string.format("stage=%d frames=%d drawn=%d closedState=%d locked=%d", d.stage, d.frames, d.drawn, d.closedState, d.lockedContext)' 2>&1); after 1 s: $(/usr/bin/sleep 1; nested_ctl repl 'local d = hl.plugin.prism.renderDiagnostics(); return string.format("stage=%d frames=%d drawn=%d", d.stage, d.frames, d.drawn)' 2>&1))"
}

# The Lua driver the real config uses, run against the real plugin in the nested
# compositor. Key presses cannot be injected, so the submap bindings are checked by
# their effect on `hyprctl submap` and the plugin calls they make are called directly.
test_driver() {
    local out
    open_test_windows
    expect_lua 'Driver load' "_G.drv = dofile('/prism-test/prism_native.lua'); return tostring(_G.drv.enabled())" true
    expect_lua 'Driver swipe up' "local g = _G.drv.gesture('up'); _G.g = g
assert(g.start({ delta = { x = 0, y = -6 }, time_ms = 1000 }), 'start refused')
assert(g.is_active())
g.update({ delta = { x = 0, y = -150 }, time_ms = 1100 })
local s = hl.plugin.prism.snapshot()
assert(s.phase == 'opening' and s.openness > 0.4, 'did not follow the fingers: ' .. s.openness)
assert(s.originWorkspace == 3, 'origin should be the active workspace 3, got ' .. tostring(s.originWorkspace))
g.finish({ cancelled = false })
assert(not g.is_active())
return s.phase" opening
    wait_phase open
    # The watcher must put the keyboard in the prism submap while it is open.
    local i submap=
    for (( i = 0; i < 30; ++i )); do
        submap=$(nested_ctl submap 2>/dev/null || true)
        [[ $submap == prism ]] && break
        /usr/bin/sleep 0.1
    done
    [[ $submap == prism ]] || fail "the keys submap was not entered while open (got: $submap)"
    printf 'Driver submap while open: %s\n' "$submap"
    expect_lua 'Driver rotate' "assert(hl.plugin.prism.rotate(1)); return 'ok'" ok
    # Rotation is a spring; wait for it to settle, then the front face is the one turned to.
    for (( i = 0; i < 50; ++i )); do
        [[ $(nested_ctl repl 'return tostring(hl.plugin.prism.snapshot().animating)') == false ]] && break
        /usr/bin/sleep 0.1
    done
    expect_lua 'Driver rotated front face' "return tostring(hl.plugin.prism.snapshot().frontWorkspace ~= 3)" true
    # Choose the front face and let the watcher focus it.
    local front
    front=$(nested_ctl repl "local p = hl.plugin.prism; local f = p.snapshot().frontWorkspace; assert(p.close(true)); return tostring(f)") \
        || fail 'could not close Prism'
    printf 'Driver closing on front workspace: %s\n' "$front"
    wait_phase closed
    for (( i = 0; i < 30; ++i )); do
        submap=$(nested_ctl submap 2>/dev/null || true)
        [[ -z $submap || $submap == default || $submap == reset ]] && break
        /usr/bin/sleep 0.1
    done
    [[ -z $submap || $submap == default || $submap == reset ]] || fail "the submap was not released after closing (got: $submap)"
    out=$(nested_ctl repl 'return tostring(hl.get_active_workspace().id)') || fail 'could not read the active workspace'
    [[ $out == "$front" ]] || fail "the watcher focused workspace $out, expected the front face $front"
    printf 'Driver active workspace after close: %s (submap released)\n' "$out"
    # Watchdog and kill switch.
    expect_lua 'Driver reset' "_G.drv.reset(); return hl.plugin.prism.snapshot().phase" closed

    # Clicks and scrolling, through the same routers the mouse listeners use. Three
    # workspaces show only the front face, so the side face is reached by scrolling.
    expect_lua 'Pointer open' "local p = hl.plugin.prism; assert(p.setWorkspaces({1, 2, 3})); assert(p.open(1)); return 'ok'" ok
    wait_phase open
    _G_front() { nested_ctl repl 'local s = hl.plugin.prism.snapshot(); return tostring(s.frontWorkspace)'; }
    expect_lua 'Pointer scroll turns' "assert(hl.plugin.prism.pointerScroll(15, true)); return 'ok'" ok
    for (( i = 0; i < 50; ++i )); do
        [[ $(nested_ctl repl 'return tostring(hl.plugin.prism.snapshot().animating)') == false ]] && break
        /usr/bin/sleep 0.1
    done
    [[ $(_G_front) == 2 ]] || fail "a scroll step did not turn to workspace 2 (front: $(_G_front))"
    printf 'Pointer scroll turned the cube to workspace 2\n'
    expect_lua 'Pointer click backdrop' "assert(hl.plugin.prism.pointerClick(0.02, 0.02)); return 'ok'" ok
    wait_phase closed
    expect_lua 'Pointer backdrop selects nothing' "return tostring(hl.plugin.prism.takeSelection())" nil
    expect_lua 'Pointer reopen' "local p = hl.plugin.prism; assert(p.open(1)); return 'ok'" ok
    wait_phase open
    expect_lua 'Pointer click front' "assert(hl.plugin.prism.pointerClick(0.5, 0.5)); return 'ok'" ok
    wait_phase closed
    expect_lua 'Pointer front click chose workspace 1' "local c = hl.plugin.prism.renderDiagnostics().clicksOwned; return tostring(hl.plugin.prism.takeSelection())" 1

    # Power tiers: full has the wallpaper, lite frees it; going back to full loads it again.
    expect_lua 'Full tier has the backdrop' "local p = hl.plugin.prism; assert(p.setQuality('full')); assert(p.setWorkspaces({1, 2, 3})); assert(p.open(1)); local d = p.renderDiagnostics(); return d.quality .. ' ' .. tostring(d.backdrop)" "full true"
    wait_phase open
    expect_lua 'Lite tier drops the backdrop' "local p = hl.plugin.prism; assert(p.close(false)); assert(p.setQuality('lite')); return 'ok'" ok
    wait_phase closed
    expect_lua 'Lite tier opens without the wallpaper' "local p = hl.plugin.prism; assert(p.open(1)); local d = p.renderDiagnostics(); return d.quality .. ' ' .. tostring(d.backdrop)" "lite false"
    wait_phase open
    expect_lua 'Lite tier still draws' "local d = hl.plugin.prism.renderDiagnostics(); return tostring(d.drawn > 0)" true
    expect_lua 'Back to full' "local p = hl.plugin.prism; assert(p.close(false)); assert(p.setQuality('full')); return 'ok'" ok
    wait_phase closed
}

# The auto-load path of the real config: opted in by a flag file, loaded from Lua. This is
# the path that did not load at login on 2026-11-24; hyprctl plugin load (used by the other
# modes) worked, so it needs its own test.
test_autoload() {
    local i loaded=
    /usr/bin/mkdir -p /run/prism/prism
    : >/run/prism/prism-native
    expect_lua 'Autoload module' "_G.drv = dofile('/prism-test/prism_native.lua'); return tostring(_G.drv.enabled())" false
    nested_ctl repl "_G.drv.start(); return 'scheduled'" >/dev/null || fail 'could not start the loader'
    for (( i = 0; i < 80; ++i )); do
        loaded=$(nested_ctl repl 'return tostring(hl.plugin ~= nil and hl.plugin.prism ~= nil)' 2>/dev/null || true)
        [[ $loaded == true ]] && break
        /usr/bin/sleep 0.1
    done
    [[ $loaded == true ]] || fail "the plugin was not loaded by prism_native.start within 8 s ($(/usr/bin/cat /run/prism/prism/load-result 2>&1); plugin list: $(nested_ctl -j plugin list 2>&1); hl.plugin keys: $(nested_ctl repl 'local k={} for n in pairs(hl.plugin) do k[#k+1]=n end return table.concat(k,",")' 2>&1))"
    printf 'Autoload: loaded by prism_native.start after about %s ms\n' "$(( i * 100 ))"
    expect_lua 'Autoload usable' "return hl.plugin.prism.snapshot().phase" closed
    expect_lua 'Autoload quality' "return hl.plugin.prism.renderDiagnostics().quality" full
}

alive() { expect_lua "Alive after $1" 'return 6 * 7' 42 >/dev/null; }

test_safety() {
    local i
    open_test_windows
    expect_lua 'Safety setup' "local p = hl.plugin.prism; assert(p.setWorkspaces({1, 2, 3})); assert(p.open(3)); return 'ok'" ok
    wait_phase open

    # A new window while open: invalidation listeners run inside the compositor.
    nested_ctl dispatch "hl.dsp.exec_cmd('kitty --config NONE --override confirm_os_window_close=0 sleep 600')" >/dev/null \
        || fail 'could not start an extra window'
    /usr/bin/sleep 2
    alive 'a window opened while open'

    # A workspace that disappears from the list while the cube is open and then chosen.
    expect_lua 'Workspace list shrinks' "local p = hl.plugin.prism; assert(p.setWorkspaces({1, 3})); assert(p.close(true)); return 'ok'" ok
    wait_phase closed
    nested_ctl repl 'hl.plugin.prism.takeSelection()' >/dev/null
    alive 'a workspace left the list mid-open'

    # Reset in the middle of the opening spring, and a second one with nothing open.
    expect_lua 'Reset mid-animation' "local p = hl.plugin.prism; assert(p.setWorkspaces({1, 2, 3})); assert(p.open(1)); assert(p.tick(0.02)); assert(p.reset()); assert(p.reset()); return p.snapshot().phase" closed
    alive 'reset in the middle of an animation'

    # Fast cycling: a swipe starts again before the last one settled.
    local reply select
    for (( i = 1; i <= 40; ++i )); do
        (( i % 2 == 0 )) && select=true || select=false
        reply=$(nested_ctl repl "local p = hl.plugin.prism; p.setWorkspaces({1, 2, 3}); p.begin('up', 2); p.update(0, -120, 0.02); p.finish(false, -400); p.begin('down', 2); p.update(0, 60, 0.02); p.finish(true); p.tick(0.016); p.close($select); p.takeSelection(); return 'x'") \
            || fail "fast cycle $i failed: $reply"
    done
    nested_ctl repl 'hl.plugin.prism.reset()' >/dev/null
    alive '40 fast open/close cycles'
    printf 'Safety diagnostics: %s\n' "$(nested_ctl repl 'local d=hl.plugin.prism.renderDiagnostics(); return string.format("captured=%d failed=%d reused=%d drawn=%d", d.captured, d.captureFailed, d.reused, d.drawn)')"

    # Unload while OPEN: PLUGIN_EXIT must tear down faces, listeners and bindings.
    expect_lua 'Open before unload' "local p = hl.plugin.prism; assert(p.setWorkspaces({1, 2, 3})); assert(p.open(2)); return 'ok'" ok
    /usr/bin/sleep 0.5
}

rss_kb() { /usr/bin/awk '/^VmRSS:/ {print $2}' "/proc/$child_pid/status"; }

diag() {
    nested_ctl repl "local d = hl.plugin.prism.renderDiagnostics(); return string.format('%d %d %d %d %d %d %d', d.frames, d.frameNsMean, d.frameNsMax, d.captureNsLast, d.captureNsMax, d.attempted, d.captureFailed)"
}

test_stress() {
    local i rss0 rss1 rss2 d0 d1 frames mean max capl capm att failed
    open_test_windows
    expect_lua 'Stress setup' "assert(hl.plugin.prism.setWorkspaces({1, 2, 3})); return 'ok'" ok

    # Idle cost: loaded but closed, the hook must do nothing: no frames drawn, no
    # attempts. (It still sees the render stage; it returns at the Closed check.)
    d0=$(diag)
    /usr/bin/sleep 3
    d1=$(diag)
    read -r _ _ _ _ _ att _ <<<"$d1"
    [[ $d0 == "$d1" ]] || fail "idle cost: counters moved while closed ($d0 -> $d1)"
    printf 'Idle while closed for 3 s: counters unchanged (%s)\n' "$d1"

    rss0=$(rss_kb)
    for (( i = 1; i <= PRISM_STRESS_CYCLES; ++i )); do
        nested_ctl repl "local p = hl.plugin.prism; assert(p.begin('up', 2)); p.update(0, -180, 0.05); p.finish(false, -600); return 'x'" >/dev/null \
            || fail "stress cycle $i: could not open"
        /usr/bin/sleep 0.25
        [[ ${PRISM_STRESS_VERBOSE-} == 1 ]] && printf 'cycle %s after open: %s\n' "$i" "$(nested_ctl repl 'local s = hl.plugin.prism.snapshot(); local d = hl.plugin.prism.renderDiagnostics(); return string.format("%s open=%.3f anim=%s stage=%d frames=%d closedState=%d attempted=%d", s.phase, s.openness, tostring(s.animating), d.stage, d.frames, d.closedState, d.attempted)')"
        nested_ctl repl "local p = hl.plugin.prism; p.rotate(1); return 'x'" >/dev/null
        /usr/bin/sleep 0.15
        nested_ctl repl "local p = hl.plugin.prism; p.close($([[ $((i % 2)) == 0 ]] && echo true || echo false)); return 'x'" >/dev/null \
            || fail "stress cycle $i: could not close"
        /usr/bin/sleep 0.25
        nested_ctl repl 'hl.plugin.prism.takeSelection() return 1' >/dev/null
        (( i == 10 || i == PRISM_STRESS_CYCLES )) && rss1=${rss1:-$(rss_kb)}
    done
    wait_phase closed
    /usr/bin/sleep 1
    rss2=$(rss_kb)
    read -r frames mean max capl capm att failed <<<"$(diag)"
    alive '100 stress cycles'
    printf 'Stress: RSS %s kB at start, %s kB after 10 cycles, %s kB after 100 (growth after warm-up: %s kB)\n' "$rss0" "$rss1" "$rss2" "$((rss2 - rss1))"
    printf 'Stress: %s frames drawn, frame mean %s us, max %s us; capture last %s us, max %s us; capture failures %s\n' \
        "$frames" "$((mean / 1000))" "$((max / 1000))" "$((capl / 1000))" "$((capm / 1000))" "$failed"
    (( failed == 0 )) || fail 'some workspace captures failed'
    (( rss2 - rss1 < 40000 )) || fail "memory kept growing after warm-up: $((rss2 - rss1)) kB over 90 cycles"
}

cleanup_nested() {
    local result=$?
    local i
    if (( result != 0 )) && [[ -f $log ]]; then
        printf '\nLast lines from nested Hyprland:\n' >&2
        /usr/bin/tail -n 60 "$log" >&2
    fi
    if child_is_hyprland; then
        kill -TERM "$child_pid" 2>/dev/null || true
        for (( i = 0; i < 20; ++i )); do
            child_is_hyprland || break
            /usr/bin/sleep 0.1
        done
        if child_is_hyprland; then
            kill -KILL "$child_pid" 2>/dev/null || true
        fi
    fi
}

test_nested() {
    local mode=$1 cycles=$2
    local log="$XDG_RUNTIME_DIR/hyprland.log"
    local config="$XDG_RUNTIME_DIR/hyprland.lua"
    local child_socket=wayland-1
    local child_pid= signature= monitor= config_errors= plugins= reply= cycle
    local build_abi version
    local harness_pid=$BASHPID
    local deadline=$((SECONDS + 15))
    local plugin=/prism-test/prism.so

    if [[ $mode == --screenshot ]]; then
        # Send only the PNG to the caller's temporary file.
        exec 3>&1 1>&2
    fi
    if (( cycles > 0 )); then
        build_abi=$(check_plugin_abi "$plugin") || exit 1
    fi

    umask 077
    ulimit -c 0
    cat >"$config" <<'LUA'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.config({
    debug = { disable_logs = false },
    ecosystem = { enforce_permissions = false, no_update_news = true, no_donation_nag = true },
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
    xwayland = { enabled = false },
})
LUA

    /usr/bin/Hyprland --config "$config" >"$log" 2>&1 3>&- &
    child_pid=$!
    trap cleanup_nested EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    while (( SECONDS < deadline )); do
        kill -0 "$child_pid" 2>/dev/null || fail 'nested Hyprland exited during startup'
        if signature=$(find_instance 2>/dev/null); then
            if [[ ${PRISM_NESTED_BACKEND-wayland} == headless && -z ${headless_created-} ]]; then
                # No host window: the headless backend has no output until one is created,
                # and it renders on its own clock, so a host workspace switch cannot stall it.
                # The Wayland backend must exist for Hyprland to start, but its output is a host
                # window that only renders while the host shows it. Switch it off and render on
                # the headless output, which runs on its own clock.
                if nested_ctl output create headless >/dev/null 2>&1; then
                    headless_created=1
                    nested_ctl repl 'hl.monitor({ output = "WAYLAND-1", disabled = true }) hl.monitor({ output = "HEADLESS-1", mode = "1280x800@60", position = "0x0", scale = 1 }) return 1' >/dev/null 2>&1 || true
                fi
            fi
            monitor=$(nested_ctl -j monitors | /usr/bin/jq -er '
                select(type == "array" and length == 1) | .[0]
                | select((.hardwareDetails.backend == "wayland" or .hardwareDetails.backend == "headless") and .width > 0 and .height > 0)
                | "\(.name) \(.width)x\(.height)"
            ') && break
        fi
        /usr/bin/sleep 0.1
    done
    if [[ -z $monitor ]]; then
        printf 'monitors: %s\n' "$(nested_ctl -j monitors 2>&1 | /usr/bin/jq -c '[.[]|{name,backend:.hardwareDetails.backend,width,height}]' 2>&1 | /usr/bin/head -c 600)" >&2
        printf 'create: %s\n' "$(nested_ctl output create headless 2>&1 | /usr/bin/head -c 300)" >&2
        /usr/bin/tail -n 30 "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log >&2 2>/dev/null || true
        fail 'no usable output before timeout'
    fi

    config_errors=$(nested_ctl -j configerrors) || fail 'could not read nested config errors'
    /usr/bin/jq -e 'type == "array" and all(.[]; . == "")' <<<"$config_errors" >/dev/null \
        || fail "nested config errors: $config_errors"
    plugins=$(nested_ctl -j plugin list) || fail 'could not read the nested plugin list'
    /usr/bin/jq -e '. == []' <<<"$plugins" >/dev/null \
        || fail "expected an empty nested plugin list: $plugins"
    printf 'Nested PID %s, signature %s, Wayland output %s, plugin list %s\n' \
        "$child_pid" "$signature" "$monitor" "$plugins"
    expect_lua 'Nested Lua readback' 'return 6 * 7' 42

    if (( cycles > 0 )); then
        version=$(nested_ctl -j version) || fail 'could not read nested Hyprland version'
        /usr/bin/jq -e --arg abi "$build_abi" '.abiHash == $abi' <<<"$version" >/dev/null \
            || fail "nested Hyprland ABI differs from plugin ABI $build_abi"
        printf 'Nested Hyprland and Prism ABI: %s\n' "$build_abi"
    fi

    for (( cycle = 1; cycle <= cycles; ++cycle )); do
        if [[ $mode != --autoload ]]; then
            reply=$(nested_ctl plugin load "$plugin") || fail "cycle $cycle load: $reply"
            [[ $reply == ok ]] || fail "cycle $cycle load: $reply"
            plugins=$(nested_ctl -j plugin list) || fail "cycle $cycle: could not read loaded plugins"
            /usr/bin/jq -e 'type == "array" and length == 1 and .[0].name == "Prism"' <<<"$plugins" >/dev/null \
                || fail "cycle $cycle: expected Prism in plugin list: $plugins"
        fi

        case $mode in
            --gesture) test_gestures ;;
            --screenshot) capture_nested "${monitor%% *}" ;;
            --driver) test_driver ;;
            --autoload) test_autoload ;;
            --safety) test_safety ;;
            --stress) test_stress ;;
        esac

        reply=$(nested_ctl plugin unload "$plugin") || fail "cycle $cycle unload: $reply"
        [[ $reply == ok ]] || fail "cycle $cycle unload: $reply"
        plugins=$(nested_ctl -j plugin list) || fail "cycle $cycle: could not read unloaded plugins"
        /usr/bin/jq -e '. == []' <<<"$plugins" >/dev/null \
            || fail "cycle $cycle: expected an empty plugin list: $plugins"
        if [[ $mode == --gesture || $mode == --screenshot || $mode == --driver || $mode == --safety || $mode == --stress || $mode == --autoload ]]; then
            expect_lua 'Prism Lua namespace after unload' 'return type(hl.plugin.prism)' nil
        fi
        printf 'Cycle %s/%s on PID %s: [] -> [Prism] -> []\n' "$cycle" "$cycles" "$child_pid"
    done
    exit 0
}

if [[ ${1-} == --inside ]]; then
    [[ $0 == /prism-test/nested.sh && ${XDG_RUNTIME_DIR-} == /run/prism \
        && ${WAYLAND_DISPLAY-} == /run/prism-parent && -S /run/prism-parent ]] \
        || fail 'the internal entry point requires the isolated mount layout'
    test_nested "$2" "$3"
fi

mode=${1-}
cycles=0
plugin_mount=()
screenshot_output=
test_windows=0
case $mode in
    --check)
        [[ $# == 1 ]] || fail 'usage: nested.sh --check'
        ;;
    --lifecycle|--gesture|--screenshot|--driver|--safety|--stress|--autoload)
        shift
        cycles=1
        if [[ $mode == --lifecycle ]]; then
            cycles=10
            if [[ ${1-} == --cycles ]]; then
                [[ ${2-} =~ ^([1-9][0-9]?|100)$ ]] || fail '--cycles must be from 1 to 100'
                cycles=$2
                shift 2
            fi
        elif [[ $mode == --screenshot ]]; then
            screenshot_output=${1-}
            screenshot_name=${screenshot_output##*/}
            [[ $screenshot_output == /tmp/* && -n $screenshot_name ]] \
                || fail 'specify a new screenshot file under /tmp'
            screenshot_dir=$(/usr/bin/realpath -e -- "${screenshot_output%/*}") \
                || fail 'the screenshot directory does not exist'
            [[ -d $screenshot_dir && ( $screenshot_dir == /tmp || $screenshot_dir == /tmp/* ) ]] \
                || fail 'the screenshot directory must resolve under /tmp'
            screenshot_output="$screenshot_dir/$screenshot_name"
            [[ ! -e $screenshot_output && ! -L $screenshot_output ]] \
                || fail "screenshot path already exists: $screenshot_output"
            [[ -x /usr/bin/grim && -x /usr/bin/file ]] || fail 'grim and file are required for screenshots'
            shift
            if [[ ${1-} == --windows ]]; then
                test_windows=1
                shift
            fi
        fi
        [[ $# -le 1 ]] || fail "extra arguments for $mode, see --help"
        script_path=$(/usr/bin/realpath -e -- "$0")
        plugin=${1:-${script_path%/*}/../build/prism.so}
        [[ -f $plugin && -r $plugin ]] || fail "build the plugin or specify a readable shared object: $plugin"
        plugin_mount=(--ro-bind "$plugin" /prism-test/prism.so
            --ro-bind "${script_path%/*}/../../../config/prism_native.lua" /prism-test/prism_native.lua)
        ;;
    --help|-h|'')
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

[[ $EUID != 0 ]] || fail 'run this as your desktop user'
for tool in bwrap Hyprland hyprctl jq; do
    [[ -x /usr/bin/$tool ]] || fail "missing /usr/bin/$tool"
done

parent_socket=${WAYLAND_DISPLAY-}
[[ -n $parent_socket ]] || fail 'WAYLAND_DISPLAY is empty'
if [[ $parent_socket != /* ]]; then
    [[ ${XDG_RUNTIME_DIR-} == /* ]] || fail 'XDG_RUNTIME_DIR is missing or relative'
    parent_socket="$XDG_RUNTIME_DIR/$parent_socket"
fi
[[ -S $parent_socket && -w $parent_socket ]] || fail "cannot access Wayland socket $parent_socket"

render_nodes=()
for node in /dev/dri/renderD*; do
    if [[ -c $node && -r $node && -w $node ]]; then
        render_nodes+=(--dev-bind "$node" "$node")
    fi
done
(( ${#render_nodes[@]} > 0 )) || fail 'no accessible GPU render node in /dev/dri'

script_path=$(/usr/bin/realpath -e -- "$0")

# A test wallpaper, mounted where the plugin looks for yours (HOME is /run/prism/home in the
# sandbox). A left-to-right magenta to teal gradient: nothing like the dark clear colour or
# the window colours, so a screenshot can tell the backdrop from a flat fill. Optional: with
# no Python Pillow the nested instance simply has no wallpaper (lite look).
wallpaper_mount=()
wallpaper_file=
if /usr/bin/python3 -I -c 'import PIL' 2>/dev/null; then
    wallpaper_file=$(/usr/bin/mktemp --tmpdir prism-test-wallpaper.XXXXXX.jpg)
    trap '/usr/bin/rm -f -- "$wallpaper_file"' EXIT
    /usr/bin/python3 -I - "$wallpaper_file" <<'PY' || wallpaper_file=
import sys
from PIL import Image
w, h = 1924, 982
im = Image.new('RGB', (w, h))
px = im.load()
for x in range(w):
    t = x / (w - 1)
    c = (int(200 * (1 - t) + 20 * t), int(40 * (1 - t) + 160 * t), int(160 * (1 - t) + 200 * t))
    for y in range(h):
        px[x, y] = c
im.save(sys.argv[1], 'JPEG', quality=90)
PY
    [[ -n $wallpaper_file ]] && wallpaper_mount=(--ro-bind "$wallpaper_file" /run/prism/home/Pictures/Wallpaper/current_wallpaper)
fi

# Aquamarine tries DRM before Wayland. Keep DRM card devices and seat sockets
# outside the namespace, while letting the Wayland backend open its render node.
sandbox=(/usr/bin/bwrap \
    --unshare-user --unshare-pid --unshare-net --unshare-ipc --unshare-uts \
    --disable-userns --die-with-parent --new-session --clearenv \
    --ro-bind /usr /usr --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib /lib64 \
    --ro-bind /etc/passwd /etc/passwd --ro-bind /etc/group /etc/group \
    --ro-bind /sys /sys --proc /proc --dev /dev --dir /dev/dri \
    "${render_nodes[@]}" \
    --tmpfs /tmp --tmpfs /run --dir /run/prism --chmod 0700 /run/prism \
    --dir /run/prism/home "${wallpaper_mount[@]}" --ro-bind "$parent_socket" /run/prism-parent \
    --ro-bind "$script_path" /prism-test/nested.sh "${plugin_mount[@]}" \
    --chdir /run/prism/home --setenv PATH /usr/bin --setenv HOME /run/prism/home \
    --setenv XDG_RUNTIME_DIR /run/prism --setenv WAYLAND_DISPLAY /run/prism-parent \
    --setenv AQ_BACKENDS "${PRISM_NESTED_BACKEND:-headless}" --setenv PRISM_NESTED_BACKEND "${PRISM_NESTED_BACKEND:-headless}" --setenv HYPRLAND_NO_RT 1 --setenv HYPRLAND_NO_SD_VARS 1 --setenv HYPRLAND_NO_SD_NOTIFY 1 \
    --setenv PRISM_NATIVE_FLAG /run/prism/prism-native --setenv PRISM_NATIVE_SO /prism-test/prism.so --setenv GSETTINGS_BACKEND memory --setenv PRISM_TEST_WINDOWS "$test_windows" --setenv PRISM_STRESS_VERBOSE "${PRISM_STRESS_VERBOSE:-0}" --setenv PRISM_STRESS_CYCLES "${PRISM_STRESS_CYCLES:-100}" -- \
    /usr/bin/bash /prism-test/nested.sh --inside "$mode" "$cycles")

if [[ $mode != --screenshot ]]; then
    # Not exec: the EXIT trap must remove the temporary wallpaper.
    "${sandbox[@]}"
    exit $?
fi

screenshot_temp=$(/usr/bin/mktemp --tmpdir="$screenshot_dir" .prism-screenshot.XXXXXX)
trap '/usr/bin/rm -f -- "$screenshot_temp" "$wallpaper_file"' EXIT
"${sandbox[@]}" >"$screenshot_temp"
[[ $(/usr/bin/file -b --mime-type -- "$screenshot_temp") == image/png ]] \
    || fail 'the nested capture did not produce a PNG'
/usr/bin/ln -T -- "$screenshot_temp" "$screenshot_output" \
    || fail "could not publish screenshot to $screenshot_output"
printf 'Saved nested Prism screenshot to %s\n' "$screenshot_output"
if [[ $test_windows == 1 ]]; then
    # Content gate: the front face must show workspace 2's green window and a side
    # face workspace 1's red one. A flat placeholder pane has neither.
    /usr/bin/python3 -I - "$screenshot_output" <<'PY' || fail 'the screenshot does not show the workspace windows on the faces'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
green = red = blue = 0
for r, g, b in im.getdata():
    if abs(r - 0x18) < 24 and abs(g - 0xa0) < 24 and abs(b - 0x30) < 24: green += 1
    if abs(r - 0xc0) < 24 and abs(g - 0x18) < 24 and abs(b - 0x18) < 24: red += 1
    if abs(r - 0x20) < 24 and abs(g - 0x40) < 24 and abs(b - 0xd0) < 24: blue += 1
print(f'Face content pixels: green={green} red={red} blue={blue}')
need = im.width * im.height // 200  # 0.5 % of the screen each
sys.exit(0 if green > need and red > need else 1)
PY
fi
