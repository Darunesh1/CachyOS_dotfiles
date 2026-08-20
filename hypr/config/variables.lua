-- ═══════════════════════════════════════════════════════════════════════════
-- ENVIRONMENT VARIABLES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Programs ($terminal, $fileManager, $menu) and the main modifier now live in
-- config/lib.lua, since Lua has no hyprlang-style `$var` interpolation.
-- ═══════════════════════════════════════════════════════════════════════════

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Theming & Platform Variables
hl.env("GTK_THEME", "Adwaita:dark")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("ADW_DISABLE_PORTAL", "1")

-- SSH agent socket
-- This pointed at $XDG_RUNTIME_DIR/keyring/ssh, a socket that is never created:
-- gnome-keyring dropped its ssh-agent component (50.0 accepts only
-- `--components=pkcs11,secrets`), so `ssh-add -l` failed with "Error connecting
-- to agent". The replacement is gcr-ssh-agent.socket, which listens here and
-- must be enabled with:  systemctl --user enable --now gcr-ssh-agent.socket
hl.env("SSH_AUTH_SOCK", (os.getenv("XDG_RUNTIME_DIR") or "") .. "/gcr/ssh")
