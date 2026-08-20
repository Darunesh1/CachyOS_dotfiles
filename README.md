# MyArch

[![Documentation](https://img.shields.io/badge/docs-view-blue?style=flat-square)](https://darriour.github.io/MyArch/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

A modern, minimalist, and highly dynamic Hyprland configuration for Arch Linux.

## ✨ Features

- 🎨 **Dynamic Theming**: Entire system colors (Hyprland, Waybar, SwayOSD, Hyprlock, Rofi, Kitty, Zsh) automatically adapt to your wallpaper via `wallust`.
- 🚀 **Performance Optimized**: High-performance continuous GPU usage tracking and native Waybar modules for zero-overhead monitoring.
- 🌫️ **Focus Mode**: Custom "Special Workspace Dim" effect ensures maximum productivity without blurring your status bar.
- 🛠️ **Fully Automated**: Automated wallpaper cycling with smooth transitions and instant theme synchronization.

## 📚 Documentation

For detailed setup instructions and configuration guides, visit the **[MyArch Documentation](https://darriour.github.io/MyArch/)**.

### Quick Links
- [Installation Guide](https://darriour.github.io/MyArch/installation)
- [Dynamic Theming Setup](https://darriour.github.io/MyArch/configuration/theming)
- [Hyprland Keybindings](https://darriour.github.io/MyArch/configuration/hyprland)

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
# Clone the repository
git clone https://github.com/darriour/MyArch.git
cd MyArch

# Link configurations (Run the setup script or link manually)
ln -s $(pwd)/hypr ~/.config/hypr
ln -s $(pwd)/waybar ~/.config/waybar
ln -s $(pwd)/kitty ~/.config/kitty
ln -s $(pwd)/swayosd ~/.config/swayosd
ln -s $(pwd)/wallust ~/.config/wallust
```

See the [full installation guide](https://darriour.github.io/MyArch/installation) for full dependency list and detailed setup.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.
