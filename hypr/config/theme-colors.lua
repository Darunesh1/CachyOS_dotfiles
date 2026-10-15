-- ═══════════════════════════════════════════════════════════════════════════
-- THEME COLOURS - the wallust-derived colours, in one place
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Two consumers, and they must not drift apart:
--
--   config/appearance.lua                 at config load and on every reload
--   scripts/wallpaper/set-wallpaper.sh    after every `wallust run`, via eval
--
-- The second one is why this file exists. set-wallpaper.sh used to finish with
-- a blanket `hyprctl reload` whose only purpose was to pick up the regenerated
-- border colours -- and a reload re-evaluates every config file, including
-- config/monitors.lua, whose catch-all rule put an extended display back to
-- mirroring. awww-cycle.sh calls that script every 200 s, so a display set to
-- "Extend" reverted within three and a half minutes, unattended, with no
-- apparent cause beyond "the wallpaper changed".
--
-- Keeping the fallbacks and the gradient angle here rather than duplicating
-- them at both call sites is the point: a copy in a shell script would drift
-- the first time one of them changed.

local M = {}

local WALLUST = (os.getenv("HOME") or "") .. "/.config/hypr/config/wallust.lua"

-- Used when wallust has never run, or when its output is unreadable. Matching
-- the values appearance.lua used to carry inline.
local DEFAULTS = {
    active_border   = { "rgba(33ccffee)", "rgba(00ff99ee)" },
    inactive_border = "rgba(595959aa)",
    shadow          = "rgba(1a1a1aee)",
}

M.border_angle = 45

-- `dofile` on an absolute path rather than `require("config/wallust")`, for
-- two reasons: there is no module cache to go stale (the trap appearance.lua
-- used to work around by hand with `package.loaded[...] = nil`), and it behaves
-- identically inside a `hyprctl eval` chunk, where it is not worth relying on
-- the config loader still resolving "config/..." names.
function M.read()
    local ok, w = pcall(dofile, WALLUST)
    if not ok or type(w) ~= "table" then w = {} end
    return {
        active_border   = type(w.active_border) == "table" and w.active_border or DEFAULTS.active_border,
        inactive_border = w.inactive_border or DEFAULTS.inactive_border,
        shadow          = w.shadow or DEFAULTS.shadow,
    }
end

-- Push the current colours into the running compositor and touch nothing else.
-- This is what replaced the `hyprctl reload` in set-wallpaper.sh.
--
-- Verified that a partial hl.config merges rather than resetting siblings, and
-- that it does so three levels deep: after applying only these three values,
-- `decoration:shadow:range` stayed 4, `decoration:rounding` 10,
-- `decoration:blur:size` 10 and `decoration:screen_shader` unchanged.
function M.apply()
    local c = M.read()
    hl.config({
        general = {
            col = {
                active_border   = { colors = c.active_border, angle = M.border_angle },
                inactive_border = c.inactive_border,
            },
        },
        decoration = { shadow = { color = c.shadow } },
    })
end

return M
