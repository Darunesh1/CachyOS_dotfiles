# Hyprland

Hyprland is the heart of MyArch. It provides a smooth, dynamic tiling window management experience.

## Keybindings

The Hyprland config is written in **Lua** and lives in `~/.config/hypr/`, with
`hyprland.lua` requiring the modules under `config/`. MyArch uses the `Super`
(Windows) key as the primary modifier, defined once as `mainMod` in
`config/lib.lua`.

| Keybinding | Action |
|------------|--------|
| `Super + T` | Open Kitty Terminal |
| `Super + Q` | Kill Active Window |
| `Super + E` | Open File Manager (Thunar) |
| `Super + Shift + E` | Find a File by Name (Rofi) |
| `Super + Tab` | Switch Window Across All Workspaces (Rofi) |
| `Alt + Tab` | Cycle Windows in the Current Workspace |
| `Super + W` | Toggle Floating |
| `Super + V` | Clipboard History (`Ctrl + Shift + Del` clears it) |
| `Super + A` | Open Rofi Launcher |
| `Super + S` | Toggle Special Workspace (Scratchpad) |
| `Super + L` | Lock Screen (Hyprlock) |

## Focus & Decoration

MyArch is configured for maximum focus and minimal distraction.

### Special Workspace (Scratchpad)

When you toggle the special workspace (`Super + S`), MyArch applies a **Dim Effect** instead of a full-screen blur. This ensures that:
1. Your primary windows are darkened to reduce distraction.
2. **Waybar remains crisp and readable** at the top of the screen.

You can adjust this in `~/.config/hypr/config/appearance.lua`:

```lua
hl.config({
    decoration = {
        dim_special = 0.5, -- Adjust between 0.0 and 1.0
    },
})
```

### Window Rules

MyArch includes several rules to improve the user experience:
- **Rofi**: Automatically centered on the cursor.
- **XWayland**: Fixes for dragging issues.
- **Floating Windows**: Specific apps like `pavucontrol` are set to float by default.

Rules are defined in `~/.config/hypr/config/rules.lua`.
