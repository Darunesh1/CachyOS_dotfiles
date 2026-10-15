-- ═══════════════════════════════════════════════════════════════════════════
-- MONITORS
-- ═══════════════════════════════════════════════════════════════════════════
--
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
--
-- Everything measured below was measured on Hyprland 0.56.2 with
-- `configProvider: lua`, using `hyprctl output create headless` as a stand-in
-- for an HDMI cable (the catch-all rule matches it exactly as a real connector
-- does). Re-run the probes if the compositor is updated.

-- ── The laptop panel ────────────────────────────────────────────────────────
--
-- `disabled = false` is spelled out on purpose, and it is the single most
-- important line in this file.
--
-- A monitor rule MERGES into the output's existing rule; it does not replace
-- it. Measured twice: after `scale = 2`, a later rule omitting `scale` left it
-- at 2; after `disabled = true`, a later rule omitting `disabled` left the
-- monitor off. So the previous version of this rule -- which never named
-- `disabled` -- re-applied cleanly on every reload and left a panel switched
-- off by "External screen only" switched off. The screen stayed black through
-- reload after reload.
--
-- Naming it makes `hyprctl reload` (SUPER + SHIFT + R) an unconditional way
-- back to a lit screen, which matters more than it looks: a config reload is
-- the ONLY path that re-enables a monitor synchronously. Monitor rules are
-- otherwise applied from a `render.preChecks` listener, and
-- `CMonitorFrameScheduler::canRender()` is false while a monitor is disabled,
-- so an `hl.monitor` eval issued when nothing is rendering can be queued and
-- never applied (upstream discussion #15437). `CConfigManager::reload()` calls
-- `scheduleReload()` and `ensureMonitorStatus()` back to back instead.
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
    mirror   = "",
    disabled = false,
})

-- ── Everything else ────────────────────────────────────────────────────────
--
-- HDMI, or DisplayPort over USB-C. An empty `output` is the catch-all rule, so
-- this covers whatever connector is used without naming any of them.
--
-- The mode comes from config/display-mode.lua, written by
-- scripts/display/display-menu.sh (SUPER + CTRL + D). Storing the choice on
-- the *catch-all* rather than under a connector name is deliberate: it means a
-- mode picked with nothing plugged in is simply what the next display gets.
-- That is what makes the menu usable without a cable.
--
-- Mirror is the default, which is the right behaviour for an unfamiliar
-- projector. Per the Hyprland source it may not be free: mirroring calls
-- `lockSoftwareForMonitor()` on the mirror SOURCE, which would force software
-- cursors for as long as a display is mirrored. That is a source reading that
-- could NOT be confirmed on this machine -- no such line appears in the log,
-- and Hyprland's own logging here is nearly silent -- so it is recorded as a
-- suspicion, not a measurement. If the desktop ever feels sluggish only while
-- a display is plugged in, this is the first thing to test.
local DEFAULT = { position = "auto", mirror = "eDP-1", disabled = false }

-- Hyprland re-evaluates this file in the SAME Lua state on `hyprctl reload`,
-- so package.loaded still holds the copy read at the last load and a stale
-- mode would win. config/appearance.lua works around the same trap for
-- config/wallust.
package.loaded["config/display-mode"] = nil
local ok, stored = pcall(require, "config/display-mode")

local m = DEFAULT
-- `type(stored) == "table"` rather than a truthiness test, because an EMPTY
-- file is valid Lua that returns nothing, and `require` then caches `true`,
-- not nil. scripts/shader-menu.sh truncates its own state file to zero bytes
-- for "None", so a 0-byte generated state file is a real case here.
--
-- Every degenerate input lands on DEFAULT: absent file (pcall true, nil),
-- empty file (true), syntax error or `return 42` (pcall false, or non-table),
-- and a table without a usable `position`. There is no input that yields a
-- dark screen.
if ok and type(stored) == "table"
    and type(stored.position) == "string" and stored.position ~= "" then
    m = {
        position = stored.position,
        mirror   = type(stored.mirror) == "string" and stored.mirror or "",
        disabled = stored.disabled == true,
    }
end

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = m.position,
    scale    = 1,
    mirror   = m.mirror,
    disabled = m.disabled,
})

-- ── Panel rescue ────────────────────────────────────────────────────────────
--
-- "External screen only" switches eDP-1 off. Unplugging the cable then leaves
-- zero enabled outputs. Hyprland 0.56 creates a headless placeholder called
-- FALLBACK (src/state/FallbackState.hpp) so the session survives, but headless
-- shows nothing -- the machine is simply dark. Confirmed from the DRM log:
-- eDP-1 `enabledState true -> false`, then HDMI `disconnected`, then nothing
-- until the cable went back in.
--
-- This hook is registered here rather than in config/autostart.lua because
-- `hyprland.start` fires once per session and not on reload, whereas this file
-- is re-evaluated on every reload -- so the hook comes back with it.
--
-- Measured: `hyprctl reload` CLEARS all hl.on subscriptions (an eval-registered
-- handler stopped firing after one reload), so handlers do NOT accumulate and
-- registration must NOT be guarded by a flag. A `_G` guard would survive the
-- reload that cleared the subscription and permanently block re-registration --
-- the rescue would silently stop working after the first reload.
--
-- The rescue is a reload, not an `hl.monitor` eval, for the frame-gating reason
-- given above the eDP-1 rule. It is safe precisely because that rule names
-- `disabled = false` and the catch-all is read from disk: the panel comes back
-- and the user's choice survives.

-- Deliberately a global. The Lua state outlives a reload (that is why the
-- package.loaded line above is needed), so this is the one thing here that can
-- remember across reloads -- which is exactly what is required to stop a reload
-- loop. A `local` would reset on the very reload it needs to count.
_G.__panel_rescue = _G.__panel_rescue or { last = 0, strikes = 0, pending = false }

-- Measured: hl.get_monitors() returns only ENABLED, NON-MIRRORING monitors,
-- matching `hyprctl monitors` rather than `hyprctl monitors all`. A monitor
-- disabled by rule vanishes from it even with `{ all = true }`, where
-- `hyprctl monitors all -j` would still list it as disabled=true:
--
--   panel only          -> 1       panel + mirroring display -> 1
--   panel + extended    -> 2       panel + disabled display  -> 1
--
-- So the length of this list is the number of lit screens, with no shell and
-- no fork. Mirrors being excluded is correct rather than merely tolerable: a
-- mirror cannot exist without a live source, so it can never be the thing
-- hiding a dark machine.
--
-- FALLBACK is excluded by name: counting it would make the guard believe there
-- is a screen to look at.
local function lit_screens()
    local n = 0
    for _, mon in ipairs(hl.get_monitors() or {}) do
        if mon.name ~= "FALLBACK" then n = n + 1 end
    end
    return n
end

local function rescue_panel()
    local g = _G.__panel_rescue
    if g.pending or lit_screens() > 0 then return end

    local now = os.time()
    if now - g.last > 30 then g.strikes = 0 end
    -- Three strikes, then stop. If three reloads in 30 s have not produced a
    -- lit screen, another one will not either, and a reload loop is worse than
    -- a dark screen with two working keybinds (SUPER + CTRL + D rescues too,
    -- and SUPER + SHIFT + R is a plain reload). Both work blind.
    if g.strikes >= 3 then return end
    g.last, g.strikes, g.pending = now, g.strikes + 1, true

    -- Deferred by a tick: never reload from inside a callback that the reload
    -- itself re-runs. Measured signature -- hl.timer(fn, { type, timeout }),
    -- timeout in milliseconds, "oneshot" fires exactly once.
    hl.timer(function()
        _G.__panel_rescue.pending = false
        hl.exec_cmd("hyprctl reload")
    end, { type = "oneshot", timeout = 100 })
end

-- Measured: monitor.removed fires for a monitor DISABLED by rule as well as for
-- one unplugged, and the handler receives a single HL.Monitor argument. Both
-- are ignored here on purpose -- the guard asks "is any screen lit?" rather
-- than "what just happened?", so it is correct whatever the payload means and
-- it does not fire spuriously when the menu disables the external for "Laptop
-- screen only" (the panel is still lit, so it returns immediately).
hl.on("monitor.removed", rescue_panel)

-- Second trigger, for a dark state that arose without a removal -- a reload
-- that applied a bad catch-all, or a hand-run eval. Only safe because of the
-- strike counter above: this is the one trigger the rescue's own reload can
-- cause.
hl.on("config.reloaded", rescue_panel)
