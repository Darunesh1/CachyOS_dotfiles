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

## Sounds

swaync does **not** play sounds itself. Its `sound-name` and `sound-file` keys are only
things a `scripts` entry can *match* on. The hook is the `scripts` block in
`config.json`: each entry has an `exec` plus regex match fields (`app-name`, `summary`,
`body`, `urgency`, `category`, `desktop-entry`, `sound-name`, `sound-file`), and
**only the first matching entry runs**, so specific apps go above the catch-all.
Source: `/etc/xdg/swaync/configSchema.json`.

| entry | matches | plays |
|---|---|---|
| `kclock-silent` | `app-name` `Clock` (kclock's timer and alarm notifications) | nothing: kclock rings by itself |
| `rencal-reminder` | `app-name` `rencal` (renCal's calendar reminders) | `alarm-clock-elapsed` |
| `critical` | urgency critical | `dialog-warning`, **even under Do Not Disturb** |
| `default` | everything else | `message-new-instant` |

Each `exec` is `notify-sound.sh <name> [always]`, which plays
`/usr/share/sounds/freedesktop/stereo/<name>.oga` with `pw-play`. The file path is full,
not a theme name, so a missing theme cannot make it fail silently.

- **Change a sound:** change the name in `config.json`. List them with
  `ls /usr/share/sounds/freedesktop/stereo/`. Then `swaync-client -R`.
- **Silence an app:** add an entry above `default` with its `app-name` and `"exec": "true"`.
  Find an app's name with `dbus-monitor "interface='org.freedesktop.Notifications',member='Notify'"`.
- **Quieter or louder:** it follows the system volume, `wpctl set-volume @DEFAULT_AUDIO_SINK@ 60%`.
- **`script-fail-notify` is off.** It defaults on, and a failing script would then raise a
  notification, which runs the script, which fails: a loop.

**Do Not Disturb does not stop scripts.** Measured: with DND on, a normal notification
still ran its script. Game Mode turns DND on, so `notify-sound.sh` checks
`swaync-client -D` itself and stays quiet unless given `always` (the critical entry does,
because swaync still shows critical notifications under DND). The sound follows the popup.

**kclock** has its own sound and does not use swaync for it. `kclockd` plays
`defaultAudioLocation` through its own audio stream (measured: a `kclockd` sink input
appeared when a 4 s test timer finished), and that property is
`/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga`, read from `kclockd` over
D-Bus. Without the entry above, every kclock notification would beep **as well** as
kclock's own alarm (also measured: the "Timer running" notification took the default
sound). Change kclock's sound and volume inside the app, not here.

**renCal** has no sound setting. Its `rencal-notifierd` service sends each reminder with
`notify-send --app-name=rencal`, and the `rencal-reminder` entry is the whole mechanism.

**kclockd starts at login by itself.** `/etc/xdg/autostart/org.kde.kclockd-autostart.desktop`
becomes a user unit through the XDG autostart generator (checked after
`systemctl --user daemon-reload`: `app-org.kde.kclockd-autostart@autostart.service`,
`PartOf=xdg-desktop-autostart.target`), so an alarm set today still rings after a reboot.
It was not running before only because kclock was installed after this session started. It
costs about 35 MiB RSS (5 MiB anonymous).

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
| Power profile | `power-profile-power-saver-symbolic`, `-balanced-`, `-performance-` |
| Screen recording | `media-record-symbolic` |
| Clipboard | `edit-paste-symbolic` |
| File finder | `system-search-symbolic` |
| Window switcher | `focus-windows-symbolic` |
| Wallpaper | `preferences-desktop-wallpaper-symbolic` |
| Shaders | `video-display-symbolic` |
| Coffee Mode | `preferences-desktop-screensaver-symbolic` |

All of them ship with Adwaita, the active icon theme. Check a new one before
using it: `find /usr/share/icons/Adwaita -name '<name>.svg'`.
