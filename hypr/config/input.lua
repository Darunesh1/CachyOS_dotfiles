-- ═══════════════════════════════════════════════════════════════════════════
-- INPUT - Keyboard, Mouse, Touchpad, Gestures
-- ═══════════════════════════════════════════════════════════════════════════

-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- ── Prism: the workspace overview, driven by the swipe itself ───────────────
--
-- Three fingers UP shrinks your screen into the middle as your fingers move, and
-- it becomes the cube; three fingers DOWN does the reverse. A different direction
-- from the horizontal workspace swipe above, so the two coexist.
--
-- `action` is a table of three callbacks rather than one function. A plain function
-- fires once, when the swipe ENDS, which is why the overview used to appear only
-- after the swipe finished. Verified in Hyprland's LuaFunctionGesture.cpp and the
-- hl.gesture parser: the fields are `start`, `update` and `finish` (NOT `end`);
-- `start` and `update` get `delta = {x, y}` PER EVENT, not cumulative, so the sum is
-- kept here; `finish` gets `cancelled`. Hyprland only starts the gesture after the
-- first ~5 units of travel, and picks up or down from those.
--
-- The callbacks stay tiny (they have a time limit and run inside the compositor):
-- one `write` per event to a tmpfs file that the overview reads with `tail -F`.
-- Measured, write to QML: median 0.65 ms, p95 1.7 ms. Spawning a process per event
-- (60 to 120 a second) was ruled out, and a FIFO was ruled out because opening one
-- for writing blocks until a reader exists, which would hang the compositor.
--
-- Lines written (quickshell/overview/shell.qml reads them):
--   B up|down            a swipe began
--   M <p>                progress, 0 (closed) to 1 (open)
--   F <cancelled> <v>    fingers lifted; v is progress per millisecond
--
-- If no overview instance is running (Game Mode, or memory was short), nothing is
-- fed; the swipe falls back to opening or closing it when the swipe ENDS, the way
-- it worked before. See scripts/overview/toggle.sh for the tiers.
local overview = require("config/lib").scripts .. "/overview/toggle.sh"
local prism = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/prism"

-- How far the fingers travel for a full open, in Hyprland's gesture units.
-- UNVERIFIED: 300 is Hyprland's own default workspace_swipe_distance, used as a
-- starting point. Make it smaller if the cube lags your fingers, larger if it
-- runs ahead of them.
local DIST = 300

-- A resident instance wrote its pid; a file left by a crash proves nothing, so the
-- pid is checked against /proc as well. Three tiny reads, once per swipe.
local function resident_alive()
    local f = io.open(prism .. "/pid", "r")
    if not f then return false end
    local pid = f:read("*l")
    f:close()
    if not pid or not pid:match("^%d+$") then return false end
    local c = io.open("/proc/" .. pid .. "/comm", "r")
    if not c then return false end
    local name = c:read("*l")
    c:close()
    return name == "qs"
end

-- Opt-in native plugin (see prism_native.lua). When it is loaded it takes the swipe;
-- otherwise everything below is exactly the Quickshell path. It loads a moment after
-- the config finishes, never during it, so a bad plugin cannot break the config.
local native = require("config/prism_native")
native.start()

local function prism_gesture(dir)
    local feed, acc, v, last_p, last_t
    local nat = native.gesture(dir)

    local function progress(e)
        if not feed or not e.delta then return end
        -- Fingers moving up make y negative.
        acc = acc + (dir == "up" and -e.delta.y or e.delta.y)
        local p = math.max(0, math.min(1, dir == "up" and acc / DIST or 1 - acc / DIST))
        local t = e.time_ms or 0
        if last_t and t > last_t then
            local inst = (p - last_p) / (t - last_t)
            v = 0.6 * v + 0.4 * inst
        end
        last_p, last_t = p, t
        feed:write("M ", string.format("%.4f", p), "\n")
    end

    return {
        start = function(e)
            if nat.start(e) then return end
            acc, v, last_p, last_t = 0, 0, dir == "up" and 0 or 1, nil
            if resident_alive() then
                feed = io.open(prism .. "/gesture", "a")
                if feed then
                    feed:setvbuf("no")
                    feed:write("B ", dir, "\n")
                    progress(e)
                    return
                end
            end
            feed = nil
            -- Nothing to drive. If there is room, start one for next time.
            hl.dispatch(hl.dsp.exec_cmd(overview .. " resident"))
        end,
        update = function(e)
            if nat.is_active() then return nat.update(e) end
            progress(e)
        end,
        finish = function(e)
            if nat.is_active() then return nat.finish(e) end
            if feed then
                feed:write("F ", e.cancelled and "1" or "0", " ", string.format("%.6f", v), "\n")
                feed:close()
                feed = nil
            elseif not e.cancelled then
                hl.dispatch(hl.dsp.exec_cmd(overview .. (dir == "up" and " open" or " close")))
            end
        end,
    }
end

hl.gesture({ fingers = 3, direction = "up",   action = prism_gesture("up") })
hl.gesture({ fingers = 3, direction = "down", action = prism_gesture("down") })

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
-- NOTE: carried over verbatim from input.conf. "epic-mouse-v1" is upstream
-- boilerplate and matches no device on this machine, so it is a no-op.
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
