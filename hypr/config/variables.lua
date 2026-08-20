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

-- SSH socket for keyring
-- Was `env = SSH_AUTH_SOCK,$XDG_RUNTIME_DIR/keyring/ssh`. Lua does not expand
-- shell variables inside strings, so read it explicitly.
hl.env("SSH_AUTH_SOCK", (os.getenv("XDG_RUNTIME_DIR") or "") .. "/keyring/ssh")
