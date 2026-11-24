-- ═══════════════════════════════════════════════════════════════════════════
-- PRISM, NATIVE: drives the C++ plugin (hypr/plugins/prism) from the swipe
-- ═══════════════════════════════════════════════════════════════════════════
--
-- OFF BY DEFAULT. The Quickshell Prism (quickshell/overview) stays the live path
-- until you opt in by creating the flag file, and it is always the fallback:
--
--     touch ~/.config/hypr/prism-native      # then SUPER + SHIFT + R (reload)
--     rm    ~/.config/hypr/prism-native      # back to Quickshell
--
-- WHY OPT-IN: the plugin runs INSIDE the compositor. A crash in it ends your whole
-- session. It has only been tested in an isolated nested Hyprland (see
-- hypr/plugins/prism/README.md and decisions/0008-*.md). Save your work first.
--
-- Nothing is loaded unless the flag file exists AND the plugin was built for this
-- exact Hyprland (the plugin itself refuses to load on an ABI mismatch, and that
-- shows up as an error here, not as a crash). Build with:
--
--     make -C ~/MyArch/hypr/plugins/prism
--
-- The callbacks stay tiny: they run inside the compositor.

local M = {}

local home = os.getenv("HOME") or ""
-- The two environment variables exist for the nested test (tests/nested.sh --autoload).
local flag = os.getenv("PRISM_NATIVE_FLAG") or (home .. "/.config/hypr/prism-native")
local so = os.getenv("PRISM_NATIVE_SO") or (home .. "/.config/hypr/plugins/prism/build/prism.so")

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

local function plugin()
    return hl.plugin and hl.plugin.prism or nil
end

-- HOW IT LOADS, and why not hl.plugin.load: measured in the nested test (tests/nested.sh
-- --autoload), hl.plugin.load(path) called after the config has been read returns nil and
-- loads NOTHING (the plugin list stays empty). That is what happened at login on
-- 2026-11-24: "tried", no error, no plugin. `hyprctl plugin load` is the path that works,
-- so it is started as a child process. Its answer goes to a file, because the only other
-- trace used to be a notification that vanished.
local runtime = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local result_dir = runtime .. "/prism"
local result_file = result_dir .. "/load-result"

local function read_result()
    local f = io.open(result_file, "r")
    if not f then return "(no answer from hyprctl)" end
    local text = f:read("*a") or ""
    f:close()
    return (text:gsub("%s+$", ""))
end

-- Starts a load when opted in and not loaded yet. The plugin appears a moment later, so
-- the return value says only whether it is usable NOW.
function M.load()
    if plugin() then return true end
    if not exists(flag) then return false end
    if not exists(so) then
        hl.notification.create({ text = "Prism native: build the plugin first (make -C hypr/plugins/prism)", timeout = 6000 })
        return false
    end
    hl.dispatch(hl.dsp.exec_cmd(string.format(
        'mkdir -p "%s" && hyprctl plugin load "%s" >"%s" 2>&1', result_dir, so, result_file)))
    return false
end

-- Called once from the config. Loads 0.8 s after the config, checks 1.5 s later, tries
-- again, and after the last try says why it failed instead of staying silent.
function M.start()
    if not exists(flag) then return end
    local function check(try)
        if plugin() then return end
        if try >= 3 then
            local why = read_result()
            hl.notification.create({ text = "Prism native did not load: " .. why, timeout = 10000 })
            return
        end
        M.load()
        hl.timer(function() check(try + 1) end, { type = "oneshot", timeout = 1500 })
    end
    hl.timer(function() check(0) end, { type = "oneshot", timeout = 800 })
end

function M.enabled()
    return plugin() ~= nil
end

-- Power-aware look. "lite" (plain backdrop, small pictures) in Power Saving and in Game
-- Mode, "full" otherwise (Balanced and Performance). Two file checks per open, no process
-- spawned. The files are written by hypr/scripts/power/{hypr-profile,game-mode}.sh. A
-- profile changed by anything else is not seen: that is the price of not spawning
-- `powerprofilesctl` inside the compositor.
local function quality()
    if exists(runtime .. "/game-mode/active") or exists(runtime .. "/prism/power-saver") then
        return "lite"
    end
    return "full"
end

local function apply_quality()
    local p = plugin()
    if p then p.setQuality(quality()) end
end

-- Numbered workspaces that exist, in order. Special workspaces have no number.
local function workspace_ids()
    local ids = {}
    for _, w in ipairs(hl.get_workspaces() or {}) do
        if type(w.id) == "number" and w.id > 0 then ids[#ids + 1] = w.id end
    end
    table.sort(ids)
    return ids
end

local function active_id()
    local w = hl.get_active_workspace()
    return w and w.id or nil
end

-- ── Keys while the cube is open ─────────────────────────────────────────────
-- A submap, so arrow keys do not leak into the app underneath. Escape and the
-- watchdog below always leave it: a stuck submap would eat your keyboard.
local in_submap = false

local function enter_keys()
    if in_submap then return end
    in_submap = true
    hl.dispatch(hl.dsp.submap("prism"))
end

local function leave_keys()
    if not in_submap then return end
    in_submap = false
    hl.dispatch(hl.dsp.submap("reset"))
end

hl.define_submap("prism", function()
    hl.bind("Right",    function() local p = plugin(); if p then p.rotate(1) end end)
    hl.bind("Left",     function() local p = plugin(); if p then p.rotate(-1) end end)
    hl.bind("Return",   function() local p = plugin(); if p then p.close(true) end end)
    hl.bind("KP_Enter", function() local p = plugin(); if p then p.close(true) end end)
    hl.bind("Escape",   function() local p = plugin(); if p then p.close(false) end end)
    -- Any other key leaves the cube open and does nothing, so a stray key is harmless.
    hl.bind("catchall", hl.dsp.no_op())
end)

-- ── Watcher: keys, selection, and a watchdog ────────────────────────────────
-- One timer chain, running only while Prism is not closed. Each tick reads the
-- state; when it has closed, it focuses the workspace that was chosen (once),
-- releases the keys, and stops. A oneshot that re-arms itself needs no cancel call.
--
-- Watchdog: if Prism has been in a non-closed state for WATCHDOG_MS with no change
-- of phase (the "it hung" case), it is reset and the keys are released.
local WATCHDOG_MS = 120000
local watching = false

local function watch()
    if watching then return end
    watching = true
    local since, last_phase = 0, nil

    local function tick()
        local p = plugin()
        if not p then
            watching = false
            leave_keys()
            return
        end
        local s = p.snapshot()
        if s.phase == "closed" then
            local chosen = p.takeSelection()
            watching = false
            leave_keys()
            -- Only a workspace that still exists: focusing a number that was closed while
            -- the cube was open would silently create an empty one.
            local exists = false
            for _, id in ipairs(workspace_ids()) do
                if id == chosen then exists = true break end
            end
            if chosen and exists and chosen ~= active_id() then
                hl.dispatch(hl.dsp.focus({ workspace = chosen }))
            end
            return
        end
        if s.phase == "open" then enter_keys() end
        -- A window dropped on another workspace in the overview. Moved silently (follow = false):
        -- without it Hyprland also switches to the destination, which would land you somewhere
        -- you did not ask to go (the same call the Quickshell version used, measured there).
        local drop = p.takeDrop()
        if drop then
            hl.dispatch(hl.dsp.window.move({ workspace = drop.workspace, follow = false, window = "address:" .. drop.window }))
            -- The faces show pictures from before the move: re-capture once it has happened.
            hl.timer(function()
                local q = plugin()
                if q then q.refresh() end
            end, { type = "oneshot", timeout = 250 })
        end
        if s.phase ~= last_phase then last_phase, since = s.phase, 0 end
        local delay = s.animating and 30 or 100
        since = since + delay
        if since >= WATCHDOG_MS then
            p.reset()
            watching = false
            leave_keys()
            hl.notification.create({ text = "Prism was stuck and was reset", timeout = 4000 })
            return
        end
        hl.timer(tick, { type = "oneshot", timeout = delay })
    end

    hl.timer(tick, { type = "oneshot", timeout = 30 })
end

-- ── The swipe ───────────────────────────────────────────────────────────────
-- Returns nil when the native path is not active, so the caller falls back.
-- `e.delta` is per event; the plugin's own distance (300 units for a full open)
-- turns it into progress. Velocity is units per second, down positive.
function M.gesture(dir)
    local active, last_t, vy = false, nil, 0

    local function feed(e)
        local p = plugin()
        if not p or not e.delta then return end
        local t = e.time_ms or 0
        local dt = (last_t and t > last_t) and (t - last_t) / 1000 or 0.016
        last_t = t
        vy = 0.6 * vy + 0.4 * (e.delta.y / dt)
        p.update(e.delta.x, e.delta.y, dt)
    end

    return {
        start = function(e)
            local p = plugin()
            if not p then return false end
            local cur = active_id()
            if not cur then return false end
            last_t, vy = nil, 0
            apply_quality()
            if not (p.setWorkspaces(workspace_ids()) and p.begin(dir, cur)) then return false end
            active = true
            feed(e)
            return true
        end,
        update = function(e)
            if active then feed(e) end
        end,
        finish = function(e)
            if not active then return end
            active = false
            local p = plugin()
            if p then
                p.finish(e.cancelled and true or false, vy)
                watch()
            end
        end,
        is_active = function() return active end,
    }
end

-- SUPER + O etc.: open or close without a swipe. Returns false when not native.
function M.toggle()
    local p = plugin()
    if not p then return false end
    local s = p.snapshot()
    if s.phase == "closed" then
        local cur = active_id()
        if not cur then return true end
        apply_quality()
        p.setWorkspaces(workspace_ids())
        p.open(cur)
    else
        p.close(true)
    end
    watch()
    return true
end

-- Emergency: always safe, always works.
function M.reset()
    local p = plugin()
    if p then p.reset() end
    watching = false
    leave_keys()
end

return M
