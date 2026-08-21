---
sidebar_position: 2
---

# Installation

This guide will walk you through installing MyArch on your Arch Linux system.

## Prerequisites

Before installing MyArch, ensure you have:

1.  **Arch Linux** installed and updated.
2.  **Git** for cloning the repository.
3.  A **Wayland-compatible GPU** (Intel, AMD, or NVIDIA with proprietary drivers).

## Step 1: Install Core Packages

Install the necessary components using `pacman`:

```bash
# Core components
sudo pacman -S hyprland waybar kitty rofi hyprlock

# Utilities
sudo pacman -S grim slurp wl-clipboard cliphist playerctl brightnessctl intel-gpu-tools

# fd powers the Super + Shift + E file finder; jq is used by the rofi menus
sudo pacman -S fd jq

# Optional but recommended
sudo pacman -S thunar firefox pavucontrol
```

Install `awww-daemon` (for wallpaper management) and `wallust` (for theming) from the AUR:

```bash
# Using yay
yay -S awww-daemon wallust-git
```

## Step 2: Clone the Repository

Clone the MyArch repository to your local machine:

```bash
git clone https://github.com/darriour/MyArch.git
cd MyArch
```

## Step 3: Create Configuration Symlinks

Link the configuration directories from the repository to your `~/.config/` folder. This ensures that changes you make in the repo are reflected in your system.

```bash
# Create symlinks
ln -s $(pwd)/hypr ~/.config/hypr
ln -s $(pwd)/waybar ~/.config/waybar
ln -s $(pwd)/kitty ~/.config/kitty
ln -s $(pwd)/rofi ~/.config/rofi
ln -s $(pwd)/swayosd ~/.config/swayosd
ln -s $(pwd)/wallust ~/.config/wallust
```

## Step 4: Generate the Theme

Several config files are generated from your wallpaper by `wallust` and are not
kept in the repository, so you must run it **once** before first launch:

```bash
wallust run ~/Pictures/Wallpaper/your-wallpaper.jpg
```

This writes the colour files for Hyprlock, Kitty, SwayOSD, Rofi and Zsh. It
matters most for Hyprlock, whose config uses `source =` on the generated file — a
hard error if it is missing, which would leave you unable to theme the lock screen.

:::note
Two files reference your wallpaper by absolute path and cannot expand `$HOME`:
`rofi/themes/launcher.rasi` and `hypr/hyprlock.conf`. Update the `/home/<user>/...`
paths in those two to match your username.
:::

## Step 5: Configure Your Monitor

The Hyprland config is written in **Lua**. Edit `~/.config/hypr/config/monitors.lua`
to match your monitor's resolution and refresh rate:

```lua
-- Find your monitor name with: hyprctl monitors
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})
```

## Step 6: Start Hyprland

You can start Hyprland from your display manager (like GDM or SDDM) by selecting the "Hyprland" session at login.

Alternatively, to start it from the TTY:

```bash
exec Hyprland
```

## Next Steps

Once you are logged in, explore the [Configuration](/category/configuration) section to learn how to customize your experience and how the dynamic theming works.
