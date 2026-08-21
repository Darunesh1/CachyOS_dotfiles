-- ═══════════════════════════════════════════════════════════════════════════
-- APPEARANCE - General, Decoration, Blur, Shadows
-- ═══════════════════════════════════════════════════════════════════════════

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
hl.config({
    general = {
        gaps_in  = 2,
        gaps_out = 4,

        border_size = 2,

        -- https://wiki.hypr.land/Configuring/Basics/Variables/#variable-types for info about colors
        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    -- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        -- https://wiki.hypr.land/Configuring/Basics/Variables/#blur
        --
        -- NOTE: appearance.conf declared blur{} TWICE. hyprlang merged them by
        -- last-write, so the values actually in effect were size=10, passes=2,
        -- special=false, with vibrancy surviving from the first block.
        -- A Lua table cannot have two `blur` keys, so they are merged here.
        -- Verified against `hyprctl getoption decoration:blur:*` before the port.
        blur = {
            enabled  = true,
            size     = 10,
            passes   = 2,
            vibrancy = 0.1696,
            special  = false, -- Disabled blurring for Waybar clarity
        },

        dim_special = 0.5, -- Added darkening instead of blurring
    },

    -- https://wiki.hypr.land/Configuring/Basics/Variables/#misc
    misc = {
        force_default_wallpaper = 0,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = true, -- If true disables the random hyprland logo / anime girl background. :(

        -- Alt+Tab used to drop out of fullscreen. Nothing was wrong with the
        -- bind: this option decides what happens when a tiled window asks for
        -- focus while another is fullscreen, and its stock value is 2
        -- (exit_fullscreen). 1 (take_over) hands the fullscreen to whichever
        -- window you cycle to, so cycling swaps windows without ever leaving
        -- fullscreen. Applies to every focus change, arrow keys included.
        on_focus_under_fullscreen = 1,
    },
})
