-- ═══════════════════════════════════════════════════════════════════════════
-- KEYBINDINGS
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Lua key syntax joins mods and key with " + ", e.g. "SUPER + SHIFT + Q",
-- replacing hyprlang's "MODS, KEY" split.
--
-- Bind flavour mapping:
--   bind   ->  hl.bind(...)
--   bindl  ->  { locked = true }
--   bindel ->  { locked = true, repeating = true }
--   bindm  ->  { mouse = true }
-- ═══════════════════════════════════════════════════════════════════════════

local L = require("config/lib")
local mainMod = L.mainMod


-- ── System ──────────────────────────────────────────────────────────────────
-- Lock screen
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))

-- Kill active window
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind("ALT + F4", hl.dsp.window.close())

-- Toggle floating
hl.bind(mainMod .. " + W", hl.dsp.window.float({ action = "toggle" }))

-- Power profile menu
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd(L.scripts .. "/power/profile-menu.sh"))

-- Shader menu (was spelled "SUPER CTRL" literally in binds.conf)
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd(L.scripts .. "/shader-menu.sh"))

-- Keybind cheat sheet (parsed from these files; the comment above a bind is its label)
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd(L.scripts .. "/rofi/keybinds.sh"))


-- ── Applications ────────────────────────────────────────────────────────────
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(L.terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(L.fileManager))
-- Find a file by name and open it. Sits next to the file manager on purpose:
-- E opens the tree, SHIFT + E searches it.
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(L.scripts .. "/rofi/find-file.sh"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(L.menu))
-- Wallpaper picker (pauses auto-cycle; "Random" resumes it)
hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd(L.scripts .. "/wallpaper/wallpaper-menu.sh"))
-- ── Emoji Picker ────────────────────────────────────────────────────────────
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("rofimoji --action type"))


-- ── Layout Controls ─────────────────────────────────────────────────────────
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.window.pseudo())        -- dwindle
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))          -- dwindle


-- ── Fullscreen ──────────────────────────────────────────────────────────────
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())                            -- normal
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" })) -- true fullscreen


-- ── Power Menu ──────────────────────────────────────────────────────────────
-- rofi, like every other menu here. Replaced wlogout, whose Suspend button
-- never actually ran its command and whose Logout needed polkit admin auth.
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd(L.scripts .. "/power/power-menu.sh"))


-- ── Reload Controls ─────────────────────────────────────────────────────────
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(L.config .. "/waybar/scripts/launch.sh")) -- Reload Waybar
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))               -- Reload Hyprland


-- ── Screenshots ─────────────────────────────────────────────────────────────
-- Long-bracket strings [[ ]] avoid escaping the embedded quotes.

-- Screenshot a selected area
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(
    [[bash -c 'mkdir -p ~/Pictures/Screenshots && grim -g "$(slurp)" - | tee ~/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png | wl-copy']]
))

-- Screenshot a selected area (Print Screen key, same as SUPER + P)
hl.bind("Print", hl.dsp.exec_cmd(
    [[bash -c 'mkdir -p ~/Pictures/Screenshots && grim -g "$(slurp)" - | tee ~/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png | wl-copy']]
))

-- Screenshot the entire screen
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
    [[bash -c 'mkdir -p ~/Pictures/Screenshots && grim - | tee ~/Pictures/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png | wl-copy']]
))

-- ── Screen Recording ────────────────────────────────────────────────────────
-- First press: select region and start recording
-- Second press: stop recording and save video
--
-- Both share one PID file, so only one recording runs at a time and either
-- key stops whichever is active.
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd(L.scripts .. "/recording/screen-record.sh"))
-- High quality: constant-quality H.264 + lossless FLAC audio in mkv
hl.bind(mainMod .. " + ALT + P", hl.dsp.exec_cmd(L.scripts .. "/recording/screen-record-hq.sh"))

-- Recording menu: pick area, resolution and sound (press again to stop)
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(L.scripts .. "/recording/record-menu.sh"))

-- ── Window Cycling (Alt + Tab) ──────────────────────────────────────────────
-- Cycle through windows in the current workspace.
-- Was two `bind = ALT, Tab` lines; collapsed into one lambda, which preserves
-- the top-to-bottom execution order.
hl.bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

-- ALT + Tab stays inside the current workspace; SUPER + Tab is the wide view:
-- every window on every workspace, with the workspace it lives on.
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd(L.scripts .. "/rofi/window-switcher.sh"))


-- ── Laptop Lid Switch ───────────────────────────────────────────────────────
-- Lock the screen and suspend when the lid is closed
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), { locked = true })
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("systemctl suspend"), { locked = true })


-- ── Window Navigation ───────────────────────────────────────────────────────
-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))


-- ── Workspaces ──────────────────────────────────────────────────────────────
-- Switch workspaces with mainMod + [0-9]
hl.bind(mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
hl.bind(mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))


-- ── Mouse Controls ──────────────────────────────────────────────────────────
-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })


-- ── Multimedia Keys (SwayOSD) ───────────────────────────────────────────────
-- Volume control (Allows up to 250% volume to match your old wpctl config)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise --max-volume 250"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("swayosd-client --output-volume lower --max-volume 250"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"),            { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle"),             { locked = true, repeating = true })

-- Brightness control
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd([[swayosd-client --brightness raise --device "*"]]), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd([[swayosd-client --brightness lower --device "*"]]), { locked = true, repeating = true })

-- Media playback (requires playerctl)
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


-- ── Clipboard Manager ───────────────────────────────────────────────────────
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(L.scripts .. "/rofi/clipboard.sh"))

-- ── OCR Snipper ─────────────────────────────────────────────────────────────
-- Capture region and extract text to clipboard
hl.bind("ALT + X", hl.dsp.exec_cmd(L.HOME .. "/.local/bin/ocr-snipper"))
