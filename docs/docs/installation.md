---
sidebar_position: 2
---

# Installation

## Prerequisites

1. **Arch Linux** (or a derivative with `pacman`), updated.
2. **Git**.
3. A **Wayland-compatible GPU** — Intel, AMD, or NVIDIA with the proprietary drivers.

## Quick install

```bash
git clone https://github.com/darriour/MyArch.git
cd MyArch
./install.sh
```

That is the whole thing. The installer is interactive — it asks before every
stage and before anything destructive, so you can run it and say no to the parts
you do not want.

It is also **idempotent**: re-running it detects what is already correct and
reports it rather than redoing the work. Nothing bad happens if you run it twice.

### What each stage does

| # | Stage | Detail |
|---|-------|--------|
| 1 | Packages | Installs everything in `packages/pacman.txt` that is missing. |
| 2 | AUR | Installs `packages/aur.txt` with `yay` or `paru`, offering to bootstrap `yay` if you have neither. |
| 3 | Backup | Moves anything it would replace into `~/.config-backup-<timestamp>/` and writes a `restore.sh` there. |
| 4 | Symlinks | Links `hypr`, `waybar`, `kitty`, `rofi`, `wallust` and `zsh` into `~/.config`, creates `~/.config/swayosd` and the directories the scripts write into. |
| 5 | Zsh | Links `~/.zshenv`, fixes the history file and `.zshrc` permissions, pre-installs zinit and its plugins, offers `chsh`. |
| 6 | Paths | Rewrites the two files that hardcode a username, and optionally tells git to ignore the change. |
| 7 | Theme | Picks a wallpaper and runs `wallust`, then verifies all five generated files exist. |
| 8 | Services | Enables `gcr-ssh-agent.socket`, masks `swaync.service`. |
| 9 | Extras | Optionally builds [ocr-snipper](https://github.com/Darunesh1/ocr-snipper) for `ALT+X`, and clones the [nvim config](https://github.com/Darunesh1/my_nvim). |
| 10 | Check | Audits the result and prints a summary. |

### Options

```bash
./install.sh --check     # run only the audit; changes nothing
./install.sh --dry-run   # print every command it would run, execute none
./install.sh --yes       # accept every prompt
./install.sh --help
```

### Undoing it

Every run that moves something aside writes a restore script next to the backup:

```bash
~/.config-backup-<timestamp>/restore.sh
```

It removes the symlinks the installer created and moves your originals back. It
only ever deletes symlinks — anything you created afterwards is left alone.

## Checking an existing setup

`./install.sh --check` re-inspects the system from scratch and reports what is
actually in place. It changes nothing, and exits non-zero if anything is
missing, so it works in a script. Reach for it whenever something stops working.

```text
══ 10/10  Final check ══

  Packages
    [  OK   ] official repo packages            40/40 installed
    [  OK   ] AUR packages                      3/3 installed

  Config links
    [  OK   ] ~/.config/hypr                    -> repo
    [  OK   ] ~/.config/swayosd                 real directory (correct)

  Zsh
    [  OK   ] ~/.zshenv                         -> repo (sets ZDOTDIR)
    [  OK   ] zinit                             installed
    [  OK   ] login shell                       zsh
    [  OK   ] prompt                            starship

  Generated theme files
    [MISSING] ~/.config/hypr/hyprlock-colors.conf  hyprlock will NOT START without this

  Systemd user units
    [  OK   ] gcr-ssh-agent.socket              active
    [  OK   ] swaync.service                    masked (correct)

  Hardware-specific (always check by hand)
    [ WARN  ] monitors.lua output               config: eDP-1   detected: eDP-1
    [ WARN  ] waybar network interface          config: wlan0   detected: wlan0
```

Statuses read as: **OK** — correct. **MISSING** — broken, and the detail column
says what breaks. **WARN** — works, but worth a look. **SKIPPED** — not
applicable here.

The two hardware rows are always warnings. They cannot be verified, only
compared: the check prints what the config says next to what it detected, and
you decide.

## Packages

Package names live in two files rather than in this page, so the docs and the
installer cannot drift apart:

- **`packages/pacman.txt`** — official repositories
- **`packages/aur.txt`** — AUR (`awww`, `wallust-git`, `rofimoji`)
- **`packages/optional.txt`** — ocr-snipper build dependencies and cosmetic extras

Each entry carries a comment explaining what breaks without it. To install them
by hand:

```bash
sudo pacman -S --needed $(grep -vE '^\s*(#|$)' packages/pacman.txt | sed 's/#.*//')
yay -S --needed $(grep -vE '^\s*(#|$)' packages/aur.txt | sed 's/#.*//')
```

:::note
The wallpaper daemon's package is **`awww`**, not `awww-daemon`. The package
ships both the `awww` and `awww-daemon` binaries.
:::

---

## Manual installation

If you would rather not run the script, this is what it does.

### 1. Packages

Install `packages/pacman.txt` and `packages/aur.txt` as shown above.

### 2. Symlinks

```bash
cd MyArch
ln -sfn "$PWD/hypr"    ~/.config/hypr
ln -sfn "$PWD/waybar"  ~/.config/waybar
ln -sfn "$PWD/kitty"   ~/.config/kitty
ln -sfn "$PWD/rofi"    ~/.config/rofi
ln -sfn "$PWD/wallust" ~/.config/wallust
ln -sfn "$PWD/zsh"     ~/.config/zsh
```

:::warning
`~/.config/swayosd` is a **plain directory**, not a symlink — there is no
`swayosd/` in this repo. The folder exists only to hold the `style.css` that
wallust writes into it.

```bash
mkdir -p ~/.config/swayosd
```
:::

Create the directories the scripts write into, or they fail at runtime —
`awww-cycle.sh` spins on an empty `shuf` without the first:

```bash
mkdir -p ~/Pictures/Wallpaper ~/Pictures/Screenshots ~/Videos/Recordings
```

### 3. Zsh

The load chain is order-sensitive, and the order is not obvious:

```
~/.zshenv  ──►  zsh/.zshenv   sets ZDOTDIR=$HOME/.config/zsh
                     │
                     └─ sources $ZDOTDIR/conf.d/*.zsh in glob order:
                        binds → core → env → prompt
                                 │
                                 └─ core.zsh drives everything and
                                    sources .zshrc LAST
```

Three things follow from that:

- **`~/.config/zsh` must be linked first.** `~/.zshenv` sets `$ZDOTDIR` to point
  at it; without the link, zsh sources nothing and you get a bare shell.
- **`zsh/.zshrc` is not the entry point.** `conf.d/core.zsh` is. `.zshrc` holds
  user overrides and is sourced at the very end.
- **`~/.zshrc` is redundant.** `$ZDOTDIR` already sends zsh to
  `~/.config/zsh/.zshrc`, and `core.zsh` sources it explicitly.

```bash
ln -sfn "$PWD/zsh/.zshenv" ~/.zshenv
touch "$PWD/zsh/.zsh_history"     # else core.zsh nags on every shell
chmod +r "$PWD/zsh/.zshrc"        # the deferred-load hook toggles this bit
chsh -s "$(command -v zsh)"
```

If you already have a `~/.zsh_history`, move it to `zsh/.zsh_history` rather
than creating an empty one — that is exactly what `core.zsh` asks for.

Plugins are managed by **zinit**, which `zsh/plugin.zsh` clones on the first
interactive shell and then uses to fetch eleven plugins over the network. That
first launch takes a minute. To get it over with up front:

```bash
git clone https://github.com/zdharma-continuum/zinit.git \
    "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
zsh -i -c exit
```

The prompt is **starship** if it is installed, falling back to
**powerlevel10k**. This repo ships a config for neither, so whichever is found
runs with its own defaults.

### 4. Per-user paths

Two files reference the wallpaper by absolute path, and neither format expands
`$HOME` — rofi's `.rasi` has no variable expansion, and hyprlock takes the
`path` key literally:

- `rofi/themes/launcher.rasi`
- `hypr/hyprlock.conf`

```bash
sed -i -E "s|/[^\"[:space:]]*/Pictures/Wallpaper|$HOME/Pictures/Wallpaper|g" \
    rofi/themes/launcher.rasi hypr/hyprlock.conf
```

Both are tracked files, so this leaves a permanent local diff. To stop git
noticing:

```bash
git update-index --skip-worktree rofi/themes/launcher.rasi hypr/hyprlock.conf
```

### 5. Generate the theme

Five config files are generated from your wallpaper by `wallust` and are
gitignored, so a fresh clone has none of them. Run it **once** before first
launch:

```bash
wallust run ~/Pictures/Wallpaper/your-wallpaper.jpg
ln -sfn ~/Pictures/Wallpaper/your-wallpaper.jpg ~/Pictures/Wallpaper/current_wallpaper
```

:::danger
`hyprlock.conf` does `source = ~/.config/hypr/hyprlock-colors.conf`. A missing
source file is a **hard error** — hyprlock will not start, and you cannot unlock
a screen you could not lock. Do not skip this step.
:::

This writes the colour files for Hyprlock, Kitty, SwayOSD, Rofi and Zsh.

### 6. Systemd user units

```bash
systemctl --user enable --now gcr-ssh-agent.socket
systemctl --user mask swaync.service
```

The first serves `$XDG_RUNTIME_DIR/gcr/ssh`, which `variables.lua` points
`SSH_AUTH_SOCK` at — without it `ssh-add` reports *Error connecting to agent*.
The second is necessary because swaync is started from `autostart.lua`; left
unmasked, D-Bus activates a second copy that fails against the bus name the
first already holds and leaves a permanently failed unit.

### 7. Configure your monitor

The Hyprland config is written in **Lua**. Edit `hypr/config/monitors.lua` to
match your display:

```lua
-- Find your monitor name with: hyprctl monitors
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
})
```

Check `waybar/config.jsonc` too — the network module is pinned to `wlan0`.

### 8. Start Hyprland

Select the "Hyprland" session at your display manager, or from a TTY:

```bash
exec Hyprland
```

## Next steps

Explore the [Configuration](/category/configuration) section to learn how to
customize your setup and how the dynamic theming works.
