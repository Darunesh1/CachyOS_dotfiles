-- ═══════════════════════════════════════════════════════════════════════════
-- WINDOW & WORKSPACE RULES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Rules are evaluated top to bottom, so order matters.
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Workspace Rules ─────────────────────────────────────────────────────────
-- "Smart gaps" / "No gaps when only"
-- Uncomment all if you wish to use that.
--
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
--
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--
--     border_size = 0,
--     rounding    = 0,
-- })
--
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--
--     border_size = 0,
--     rounding    = 0,
-- })


-- ── Window Rules ────────────────────────────────────────────────────────────
-- For rofi - center on cursor
hl.window_rule({
    name  = "rofi-mouse-follow",
    match = { class = "^(rofi)$" },

    float = true,
    move  = "cursor -50% -50%",
})

-- Ignore maximize requests from all apps
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    -- NOTE: a rule-engine expression, not arithmetic. Keep it a string.
    move  = "20 monitor_h-120",
    float = true,
})

-- Calculator and Obsidian: float, small, centred.
--
-- Classes measured with `hyprctl clients -j` on the running apps rather than
-- guessed from the binary name: gnome-calculator reports
-- `org.gnome.Calculator` and obsidian reports `md.obsidian.Obsidian`. Both are
-- also the `initialClass`, so matching on `class` is stable here.
--
-- `center = true` was verified to work on this build: a 700-wide rule landed at
-- x = 610 on a 1920-wide output (exactly centred), with y offset by the waybar
-- reservation. Size is a floor, not a promise -- GNOME Calculator refused 500
-- height and came up 616, because a window's own minimum size wins.
hl.window_rule({
    name  = "float-calculator",
    match = { class = "^(org\\.gnome\\.Calculator)$" },

    float  = true,
    size   = "480 640",
    center = true,
})

hl.window_rule({
    name  = "float-obsidian",
    match = { class = "^(md\\.obsidian\\.Obsidian)$" },

    -- Pixels, not "60% 70%": a percentage size was accepted without a config
    -- error and then ignored -- Obsidian came up at the full 1920x1080. Pixels
    -- are honoured exactly (measured 1200x760 at x=360, dead centre).
    float  = true,
    size   = "1200 760",
    center = true,
})
