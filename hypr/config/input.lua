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

-- Three fingers up opens the workspace overview, three fingers down closes it.
-- (quickshell/overview, launched on demand by scripts/overview/toggle.sh.)
--
-- A different direction from the horizontal workspace swipe above, so the two
-- coexist. The action form is the one Hyprland's own hyprtester suite uses:
-- `action = function() hl.dispatch(hl.dsp.exec_cmd(...)) end`.
--
-- `close` is a no-op when the overview is not open, so a stray swipe down does
-- nothing. Both go through the script so the open/close rule lives in one place.
local overview = require("config/lib").scripts .. "/overview/toggle.sh"

hl.gesture({
    fingers   = 3,
    direction = "up",
    action    = function() hl.dispatch(hl.dsp.exec_cmd(overview .. " open")) end,
})

hl.gesture({
    fingers   = 3,
    direction = "down",
    action    = function() hl.dispatch(hl.dsp.exec_cmd(overview .. " close")) end,
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
-- NOTE: carried over verbatim from input.conf. "epic-mouse-v1" is upstream
-- boilerplate and matches no device on this machine, so it is a no-op.
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
