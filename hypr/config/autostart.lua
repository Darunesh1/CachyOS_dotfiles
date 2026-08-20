-- ═══════════════════════════════════════════════════════════════════════════
-- AUTOSTART - Startup Applications
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Replaces `exec-once =`. Everything here runs on the `hyprland.start` event,
-- which fires once per session (NOT on `hyprctl reload`).
--
-- hl.exec_cmd() spawns asynchronously and runs the string through `sh -c`,
-- so there is no need for a trailing `& disown`.
-- ═══════════════════════════════════════════════════════════════════════════

local L = require("config/lib")

hl.on("hyprland.start", function()
    -- Core services
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")

    -- Clipboard Manager - Stores text and image data
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Wallpaper Daemon
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd(L.scripts .. "/wallpaper/awww-cycle.sh")

    -- Dark Mode GSettings
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'")

    -- For hypridle
    hl.exec_cmd("hypridle")

    -- GNOME Keyring
    hl.exec_cmd("eval $(gnome-keyring-daemon --start --components=secrets,ssh,pkcs11)")

    -- Battery notifications
    hl.exec_cmd(L.scripts .. "/power/battery-notify.sh")

    -- Start SwayOSD daemon
    hl.exec_cmd("swayosd-server")

    -- Automount removable media
    hl.exec_cmd("udiskie --automount --notify")
end)
