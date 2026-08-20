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
