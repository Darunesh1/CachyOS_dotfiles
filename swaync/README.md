# swaync

Notification daemon config. JSON allows no comments, hence this note.

`config.json` only overrides the timeouts; every other key falls back to
`/etc/xdg/swaync/config.json`, and the styling falls back to
`/etc/xdg/swaync/style.css` (there is no `style.css` here on purpose).

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
