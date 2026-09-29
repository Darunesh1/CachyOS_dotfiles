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

-- ── app() : launch in its own cgroup ────────────────────────────────────────
-- Anything Hyprland spawns directly becomes a child of its own cgroup,
-- wayland-wm@hyprland.desktop.service. That is not cosmetic: systemd-oomd
-- kills whole cgroups, so with Firefox and the terminal living in the
-- compositor's cgroup the only thing oomd can kill is the entire desktop.
-- Measured on this machine, twice -- 28 and 29 Sep 2026:
--
--   systemd-oomd: Marked .../wayland-wm@hyprland.desktop.service for killing
--   wayland-wm@hyprland.desktop.service: Failed with result 'oom-kill'
--
-- Both times the session vanished to the login screen mid-work. `uwsm app --`
-- puts the process in its own scope under app.slice instead
-- (app-Hyprland-firefox-<hash>.scope), which gives oomd something to kill
-- that is not the desktop.
--
-- Only the memory-hungry apps use this. Menu and helper scripts are left
-- alone deliberately: they use almost no memory, and a shell script in its
-- own scope can see a different environment than one inheriting the
-- session's -- a real risk for the ones calling hyprctl and notify-send.
function M.app(cmd)
  return "uwsm app -- " .. cmd
end

return M
