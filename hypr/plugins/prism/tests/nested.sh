#!/usr/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: nested.sh --check
       nested.sh --lifecycle [--cycles COUNT] [PLUGIN]
       nested.sh --gesture [PLUGIN]
       nested.sh --screenshot OUTPUT [PLUGIN]

--check       Start an isolated Hyprland and verify its Wayland output.
--lifecycle   Verify Prism load and unload on the same isolated instance.
--gesture     Drive Prism's Lua callbacks and verify state before unloading.
--screenshot  Open Prism and save a PNG of the nested output before unloading.
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

capture_nested() {
    local output_name=$1 code
    code=$(cat <<'LUA'
local prism = hl.plugin.prism
assert(prism.reset())
assert(prism.setWorkspaces({1, 2, 3, 4}))
assert(prism.begin("up", 1))
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
assert(state.frontWorkspace == 1, "workspace 1 is not in front")
return state.phase
LUA
    )
    expect_lua 'Prism before capture' "$code" open
    local counters
    counters=$(nested_ctl repl 'local d=hl.plugin.prism.renderDiagnostics(); return string.format("stage=%d noctx=%d locked=%d closed=%d attempted=%d candidates=%d ready=%d enqueued=%d drawn=%d", d.stage, d.missingContext, d.lockedContext, d.closedState, d.attempted, d.candidates, d.ready, d.enqueued, d.drawn)') \
        || fail 'could not read Prism render diagnostics before capture'
    printf 'Prism render diagnostics before capture: %s\n' "$counters"
    WAYLAND_DISPLAY="$XDG_RUNTIME_DIR/$child_socket" \
        /usr/bin/timeout 10s /usr/bin/grim -t png -o "$output_name" - >&3 3>&- \
        || fail 'could not capture the nested output with grim'
    expect_lua 'Prism after capture' 'return hl.plugin.prism.snapshot().phase' open
    counters=$(nested_ctl repl 'local d=hl.plugin.prism.renderDiagnostics(); return string.format("stage=%d noctx=%d locked=%d closed=%d attempted=%d candidates=%d ready=%d enqueued=%d drawn=%d", d.stage, d.missingContext, d.lockedContext, d.closedState, d.attempted, d.candidates, d.ready, d.enqueued, d.drawn)') \
        || fail 'could not read Prism render diagnostics'
    printf 'Prism render diagnostics: %s\n' "$counters"
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
            monitor=$(nested_ctl -j monitors | /usr/bin/jq -er '
                select(type == "array" and length == 1) | .[0]
                | select(.hardwareDetails.backend == "wayland" and .width > 0 and .height > 0)
                | "\(.name) \(.width)x\(.height)"
            ') && break
        fi
        /usr/bin/sleep 0.1
    done
    [[ -n $monitor ]] || fail 'no usable Wayland output before timeout'

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
        reply=$(nested_ctl plugin load "$plugin") || fail "cycle $cycle load: $reply"
        [[ $reply == ok ]] || fail "cycle $cycle load: $reply"
        plugins=$(nested_ctl -j plugin list) || fail "cycle $cycle: could not read loaded plugins"
        /usr/bin/jq -e 'type == "array" and length == 1 and .[0].name == "Prism"' <<<"$plugins" >/dev/null \
            || fail "cycle $cycle: expected Prism in plugin list: $plugins"

        case $mode in
            --gesture) test_gestures ;;
            --screenshot) capture_nested "${monitor%% *}" ;;
        esac

        reply=$(nested_ctl plugin unload "$plugin") || fail "cycle $cycle unload: $reply"
        [[ $reply == ok ]] || fail "cycle $cycle unload: $reply"
        plugins=$(nested_ctl -j plugin list) || fail "cycle $cycle: could not read unloaded plugins"
        /usr/bin/jq -e '. == []' <<<"$plugins" >/dev/null \
            || fail "cycle $cycle: expected an empty plugin list: $plugins"
        if [[ $mode == --gesture || $mode == --screenshot ]]; then
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
case $mode in
    --check)
        [[ $# == 1 ]] || fail 'usage: nested.sh --check'
        ;;
    --lifecycle|--gesture|--screenshot)
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
        fi
        [[ $# -le 1 ]] || fail "extra arguments for $mode, see --help"
        script_path=$(/usr/bin/realpath -e -- "$0")
        plugin=${1:-${script_path%/*}/../build/prism.so}
        [[ -f $plugin && -r $plugin ]] || fail "build the plugin or specify a readable shared object: $plugin"
        plugin_mount=(--ro-bind "$plugin" /prism-test/prism.so)
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
    --dir /run/prism/home --ro-bind "$parent_socket" /run/prism-parent \
    --ro-bind "$script_path" /prism-test/nested.sh "${plugin_mount[@]}" \
    --chdir /run/prism/home --setenv PATH /usr/bin --setenv HOME /run/prism/home \
    --setenv XDG_RUNTIME_DIR /run/prism --setenv WAYLAND_DISPLAY /run/prism-parent \
    --setenv HYPRLAND_NO_RT 1 --setenv HYPRLAND_NO_SD_VARS 1 --setenv HYPRLAND_NO_SD_NOTIFY 1 \
    --setenv GSETTINGS_BACKEND memory -- \
    /usr/bin/bash /prism-test/nested.sh --inside "$mode" "$cycles")

if [[ $mode != --screenshot ]]; then
    exec "${sandbox[@]}"
fi

screenshot_temp=$(/usr/bin/mktemp --tmpdir="$screenshot_dir" .prism-screenshot.XXXXXX)
trap '/usr/bin/rm -f -- "$screenshot_temp"' EXIT
"${sandbox[@]}" >"$screenshot_temp"
[[ $(/usr/bin/file -b --mime-type -- "$screenshot_temp") == image/png ]] \
    || fail 'the nested capture did not produce a PNG'
/usr/bin/ln -T -- "$screenshot_temp" "$screenshot_output" \
    || fail "could not publish screenshot to $screenshot_output"
printf 'Saved nested Prism screenshot to %s\n' "$screenshot_output"
