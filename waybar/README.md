# Waybar Setup

## Dependencies

Waybar's packages are part of the repo-wide manifest, not a separate list --
`packages/pacman.txt` is the single source of truth and `install.sh` reads it.
The entries this bar depends on are `waybar`, `pacman-contrib` (for
`checkupdates`), `intel-gpu-tools` (`intel_gpu_top`), `power-profiles-daemon`,
`pavucontrol`, `nm-connection-editor`, `swaync` and `ttf-jetbrains-mono-nerd`.

To check what is actually installed:

```bash
./install.sh --check
```

## File structure

```
~/.config/waybar/
├── config.jsonc
├── style.css
├── style/
│   └── one-dark.css
└── scripts/
    ├── updates.sh
    ├── intel-gpu.sh
    ├── coffee-mode.sh
    ├── coffee-status.sh
    └── launch.sh
```

All scripts are already mode 755 in git, so there is no `chmod` step.

## Install

`./install.sh` at the repo root symlinks `~/.config/waybar` here, so edits in
the repo take effect directly -- no copying.

To reload after a change: **SUPER + R**, or `./scripts/launch.sh`.

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
