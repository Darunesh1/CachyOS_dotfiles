# MyArch

[![Documentation](https://img.shields.io/badge/docs-view-blue?style=flat-square)](https://Darunesh1.github.io/MyArch/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

A modern, minimalist, and highly dynamic Hyprland configuration for Arch Linux.

## ✨ Features

- 🎨 **Dynamic Theming**: Entire system colors (Hyprland, Waybar, SwayOSD, Hyprlock, Rofi, Kitty, Zsh) automatically adapt to your wallpaper via `wallust`.
- 🚀 **Performance Optimized**: High-performance continuous GPU usage tracking and native Waybar modules for zero-overhead monitoring.
- 🌫️ **Focus Mode**: Custom "Special Workspace Dim" effect ensures maximum productivity without blurring your status bar.
- 🛠️ **Fully Automated**: Automated wallpaper cycling with smooth transitions and instant theme synchronization.

## 📚 Documentation

For detailed setup instructions and configuration guides, visit the **[MyArch Documentation](https://Darunesh1.github.io/MyArch/)**.

### Quick Links
- [Installation Guide](https://Darunesh1.github.io/MyArch/installation)
- [Dynamic Theming Setup](https://Darunesh1.github.io/MyArch/configuration/theming)
- [Hyprland Keybindings](https://Darunesh1.github.io/MyArch/configuration/hyprland)

## 🖥️ Components

| Component | Description |
|-----------|-------------|
| **Hyprland** | Smooth tiling window management with dynamic animations. |
| **Waybar** | Optimized status bar with real-time system monitoring. |
| **SwayOSD** | Polished, dynamically themed on-screen displays for volume and brightness. |
| **Wallust** | The engine behind the wallpaper-based color generation. |
| **Hyprlock** | Secure and aesthetically synced lock screen. |

## 🚀 Quick Install

```bash
git clone https://github.com/darriour/MyArch.git
cd MyArch
./install.sh
```

The installer is interactive: it asks before every stage and before anything
destructive, backs up whatever it would replace, and writes a `restore.sh` to
put it all back.

| Stage | What it does |
|-------|--------------|
| 1–2 | Installs packages from `packages/pacman.txt` and `packages/aur.txt` (bootstraps `yay` if you have no AUR helper) |
| 3 | Moves conflicting configs to `~/.config-backup-<timestamp>/` and generates a restore script |
| 4 | Symlinks `hypr`, `waybar`, `kitty`, `rofi`, `wallust`, `swaync`, `zsh` into `~/.config`, and creates the directories the scripts write into |
| 5 | Sets up zsh: `~/.zshenv`, `$HISTFILE`, zinit pre-warm, `chsh` |
| 6 | Rewrites the two files that hardcode a username |
| 7 | Picks a wallpaper and runs `wallust` to generate every colour file |
| 8 | Enables `gcr-ssh-agent.socket`, masks `swaync.service`, pins the login screen (noctalia-greeter) to 100% scale |
| 9 | Optionally builds [ocr-snipper](https://github.com/Darunesh1/ocr-snipper) (ALT+X) and clones the [nvim config](https://github.com/Darunesh1/my_nvim) |
| 10 | Audits the result and prints a summary of what is and is not in place |

```bash
./install.sh --check     # audit an existing setup, change nothing
./install.sh --dry-run   # show every command it would run
./install.sh --yes       # accept every prompt
```

Run `--check` any time something stops working -- it reports missing packages,
broken links, ungenerated theme files and unconfigured services, and exits
non-zero if anything is missing.

After installing, set your monitor in `hypr/config/monitors.lua` and start
Hyprland. See the [full installation guide](https://Darunesh1.github.io/MyArch/installation)
for the manual route.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.
