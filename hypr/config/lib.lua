-- ═══════════════════════════════════════════════════════════════════════════
-- SHARED VALUES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Replaces the hyprlang `$var = value` definitions, which do not exist in Lua.
-- Every other module starts with:  local L = require("config/lib")
--
-- Note: Lua does NOT expand `~` or `$HOME` in strings. Build paths from L.HOME.
-- (Strings passed to hl.exec_cmd DO get shell expansion, since it runs `sh -c`,
--  but we use explicit paths here so behaviour never depends on that.)
-- ═══════════════════════════════════════════════════════════════════════════

local M = {}

-- ── Paths ───────────────────────────────────────────────────────────────────
M.HOME = os.getenv("HOME")
M.config = M.HOME .. "/.config"
M.hypr = M.config .. "/hypr"
M.scripts = M.hypr .. "/scripts"
M.shaders = M.hypr .. "/shaders"

-- ── Modifier ────────────────────────────────────────────────────────────────
M.mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- ── Programs ────────────────────────────────────────────────────────────────
M.terminal = "kitty"
M.fileManager = "thunar"
M.menu = "rofi -show drun -theme " .. M.config .. "/rofi/themes/launcher.rasi"

return M
