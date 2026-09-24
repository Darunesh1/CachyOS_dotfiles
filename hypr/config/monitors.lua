-- ═══════════════════════════════════════════════════════════════════════════
-- MONITORS
-- ═══════════════════════════════════════════════════════════════════════════

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})

-- Everything else -- HDMI, or DisplayPort over USB-C -- mirrors the laptop
-- screen: the same picture, not a second desktop off to the right, which is
-- what Hyprland's own default gives. An empty `output` is the catch-all rule
-- (hyprlang's `monitor=,preferred,auto,1,mirror,eDP-1`), so it covers whatever
-- connector is used without naming each one.
--
-- SUPER + CTRL + D (scripts/display/display-menu.sh) switches to extend or to a
-- single screen. That lasts until the cable is pulled; replugging mirrors again,
-- because this rule is what a freshly connected monitor is matched against.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
    mirror   = "eDP-1",
})
