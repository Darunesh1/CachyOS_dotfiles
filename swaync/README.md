# swaync

Notification daemon config. JSON allows no comments, hence this note.

`config.json` only overrides the timeouts; every other key falls back to
`/etc/xdg/swaync/config.json`.

| key | stock | here | applies to |
|---|---|---|---|
| `timeout` | 10 | **5** | normal notifications |
| `timeout-low` | 5 | **3** | low urgency |
| `timeout-critical` | 0 = never | **20** | `notify-send -u critical` |

Stock `timeout-critical: 0` means a critical notification never disappears by
itself. That is why they used to sit on screen until clicked.

Nothing is lost when one expires -- it stays in the control center (the bell in
waybar, or `swaync-client -t`).

After editing: `swaync-client -R` (reload config, no restart needed).

## style.css is generated -- do not edit it here

`style.css` in this directory is written by wallust from
`wallust/templates/swaync.css`, so the notifications follow the wallpaper like
everything else. It is in `.gitignore`; edit the template, then
`wallust run ~/Pictures/Wallpaper/current_wallpaper` and `swaync-client -rs`
(CSS reload, no restart). `set-wallpaper.sh` does both on every wallpaper change.

swaync's fallback is per *file*: the moment a `style.css` exists here, the stock
one is dropped whole. The template therefore starts by importing
`/etc/xdg/swaync/style.css` and only states what differs -- so upstream's layout
keeps arriving, and the overrides stay short. A notification is a card in the
wallpaper's background colour with a coloured left edge: the accent for normal,
a **fixed** red for critical (wallust's `color1` can come out grey on a muted
wallpaper, which would make the battery emergency the least visible thing on
screen).

## One icon per task

Every `notify-send` in this repo passes `-i` with a *symbolic* icon name, so
each kind of message is recognisable at a glance and the icon takes the accent
colour (symbolic icons are drawn in the CSS `color`; full-colour ones would
ignore the theme). `-a` sets the app name, which is what swaync groups by.

| what | icon |
|---|---|
| Wi-Fi | `network-wireless-signal-excellent-symbolic`, `network-wireless-offline-symbolic` when there is no internet |
| Hotspot | `network-wireless-hotspot-symbolic` |
| Battery | `battery-caution-symbolic` (critical), `battery-low-symbolic` |
| Game Mode | `applications-games-symbolic` |
| Screen recording | `media-record-symbolic` |
| Clipboard | `edit-paste-symbolic` |
| File finder | `system-search-symbolic` |
| Window switcher | `focus-windows-symbolic` |
| Wallpaper | `preferences-desktop-wallpaper-symbolic` |
| Shaders | `video-display-symbolic` |
| Coffee Mode | `preferences-desktop-screensaver-symbolic` |

All of them ship with Adwaita, the active icon theme. Check a new one before
using it: `find /usr/share/icons/Adwaita -name '<name>.svg'`.
