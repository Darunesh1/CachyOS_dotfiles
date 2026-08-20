# Dynamic Theming

The standout feature of MyArch is its **Dynamic Theming Pipeline**. Your system's colors are not hardcoded; they are generated on-the-fly from your wallpaper.

## How it Works

The pipeline is triggered whenever your wallpaper changes (either manually or via the `awww-cycle.sh` script).

1.  **Wallpaper Selection**: `awww` (via `swww`) applies a new wallpaper with a smooth transition.
2.  **Color Extraction**: `wallust` analyzes the wallpaper and generates a color palette.
3.  **Template Generation**: `wallust` applies these colors to various templates in `~/.config/wallust/templates/`.
4.  **Distribution**: The generated configurations are sent to their respective locations:
    - **SwayOSD**: `~/.config/swayosd/style.css`
    - **Hyprlock**: `~/.config/hypr/hyprlock-colors.conf`
    - **Rofi**: `~/.config/rofi/themes/colours.rasi`
    - **Kitty**: `~/.config/kitty/kitty-theme.conf`
    - **Zsh**: `~/.config/zsh/wallust-colors.zsh`

All five are generated, so they are gitignored and absent from a fresh clone —
run `wallust run <wallpaper>` once after cloning.

## Component Breakdown

### SwayOSD (On-Screen Display)

SwayOSD handles volume and brightness popups. MyArch uses a custom template that:
- Removes the box background for a minimalist, "floating" look.
- Colors the icons and progress bars using your wallpaper's **accent color** (`color4`).

### Hyprlock (Lock Screen)

The lock screen colors are synced via a dedicated color file.
- The **Clock** and **Battery** label match your wallpaper's foreground color.
- The **Password Input** field adapts its inner color to your wallpaper's background.

### Rofi (Launcher, Clipboard, Shaders, Power Menu)

Every Rofi menu imports a single generated palette, so they all share one look.
- **Themes** in `~/.config/rofi/themes/` each begin with `@import "colours.rasi"`.
- **Selection** is highlighted with your wallpaper's accent color.
- Adding a new menu means writing its layout only — the colors come for free.

## Triggering a Manual Sync

If you want to force a theme update based on your current wallpaper, you can run:

```bash
wallust run ~/Pictures/Wallpaper/current_wallpaper && killall swayosd-server && swayosd-server > /dev/null 2>&1 & disown
```
