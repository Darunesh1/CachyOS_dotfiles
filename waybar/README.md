# Waybar Setup

## Dependencies

Install these before reloading waybar:

```bash
# Core
sudo pacman -S waybar

# For update counter
sudo pacman -S pacman-contrib      # provides checkupdates

# For power/logout menu

# For volume control popup
sudo pacman -S pavucontrol

# For network editor
sudo pacman -S nm-connection-editor

# Nerd Font (pick one)
sudo pacman -S ttf-jetbrains-mono-nerd
# or
sudo pacman -S ttf-firacode-nerd
```

## File structure

```
~/.config/waybar/
├── config.jsonc
├── style.css
├── style/
│   └── one-dark.css
└── scripts/
    ├── updates.sh       ← make executable!
    ├── intel-gpu.sh     ← make executable!
    ├── coffee-mode.sh   ← make executable!
    ├── coffee-status.sh ← make executable!
    └── launch.sh        ← make executable!
```

## Install

```bash
# Copy files
cp -r . ~/.config/waybar/

# Make scripts executable
chmod +x ~/.config/waybar/scripts/*.sh

# Reload waybar (kill & restart, or via hyprland)
pkill waybar && waybar &
```

## Notes

### Clock
- Shows **time** by default (`18:32`)
- **Click** the clock to toggle to date view (`Sat 28 Mar`)
- Hover for full tooltip with day + date + seconds

### Updates counter
- 🔘 Grey = up to date
- 🟢 Green = 1–10 pending
- 🟡 Yellow = 11–30 pending
- 🔴 Red = 31+ pending
- **Click** to open a terminal with `sudo pacman -Syu`
  → Change `kitty` in config.jsonc to your terminal if needed

### WiFi
- Shows signal strength as percentage
- Hover tooltip shows SSID, strength, IP, frequency
- **Click** to open nm-connection-editor

### Temperature
- Uses thermal_zone 0 by default
- If readings look wrong, check: `cat /sys/class/thermal/thermal_zone*/temp`
- Adjust `"thermal-zone"` in config.jsonc accordingly

### Power button (⏻)
- Opens the Rofi power menu (`hypr/scripts/power/power-menu.sh`)
- Hover turns it red as a safety cue
