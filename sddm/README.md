# sddm

The login screen: **SDDM** running [qylock](https://github.com/Darkkal44/qylock)'s
`pixel-hollowknight` theme.

qylock is not a login manager. It is a pack of 39 **SDDM themes** (plus a
separate Quickshell lock screen, which this setup does not use -- hyprlock
already follows the wallpaper through wallust, and a broken lock screen locks
you out of your own session). Using any qylock theme therefore means running
SDDM instead of the greetd + noctalia-greeter that CachyOS ships with.

What that cost, measured before switching:

| | |
|---|---|
| packages | `sddm`, `gst-plugins-base`, `gst-plugins-good` -- 8 packages with dependencies, 9.3 MB download, ~21 MB installed |
| hidden dependency | Arch's `sddm` **hard-depends on `xorg-server`**. The greeter runs under X; the session it starts is still Wayland |
| theme | 39 MB, of which `bg.mp4` is 38.7 MB |
| what is lost | the login screen no longer follows the wallpaper. noctalia's did; qylock is fixed artwork |

## Files

| here | installed to | what |
|---|---|---|
| `theme.conf` | `/etc/sddm.conf.d/10-theme.conf` | which theme is current |
| `virtualkeyboard.conf` | `/etc/sddm.conf.d/20-virtualkeyboard.conf` | `InputMethod=` -- turns off the on-screen keyboard, which qylock's README lists as a known SDDM annoyance |
| `install-theme.sh` | -- | fetches a theme and installs both files |

The theme itself is **not** in this repo: a 39 MB video does not belong in a
dotfiles history. `install-theme.sh` fetches it instead.

## Why the install script does a sparse clone

qylock's repository is **1.13 GB** -- its git history is full of 4K videos. A
plain `git clone` for one 39 MB theme is absurd, so the script uses a partial
clone plus a sparse checkout:

```bash
git clone --filter=blob:none --no-checkout --depth 1 "$REPO_URL" "$tmp"
git -C "$tmp" sparse-checkout init --cone
git -C "$tmp" sparse-checkout set "themes/$THEME"
git -C "$tmp" checkout
```

`--filter=blob:none` downloads no file contents up front; the sparse path then
limits what the checkout actually asks for. Measured: 77 MB in the temp
directory (the video once as a git object, once checked out) against 1.13 GB,
and the temp directory is deleted afterwards.

## Using it

```sh
./install-theme.sh                  # pixel-hollowknight
./install-theme.sh --list           # all 39 theme names
./install-theme.sh pixel-sakura     # a different one
```

It installs the theme and the config, and **never** touches which display
manager is enabled. That is deliberate: the theme changing is harmless, the
display manager changing is not.

## Switching, and getting back

Switch (takes effect at the next reboot):

```sh
sudo systemctl disable greetd.service
sudo systemctl enable sddm.service
```

Do **not** `systemctl stop greetd` from inside the session -- it owns vt 1 and
stopping it kills the session.

Roll back, if the login screen does not come up. `Ctrl+Alt+F2` for a text
console, log in, then:

```sh
sudo systemctl disable sddm && sudo systemctl enable greetd && sudo reboot
```

greetd and noctalia-greeter are left installed precisely so this works, and
`greetd/greeter.toml` (the 100%-scale fix) is still tracked for the same reason.

Before switching, the theme can be seen without committing to anything:

```sh
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/pixel-hollowknight
```

That draws the real login screen in a window, with greetd still in charge.

## If the video background is too much

The login screen decodes a looping video on the Intel iGPU. If that makes login
feel slow, edit `/usr/share/sddm/themes/pixel-hollowknight/theme.conf`:

```ini
background=bg.mp4
type=video        # -> type=image, with background= pointing at a still
```

Nothing else in the theme has to change.
