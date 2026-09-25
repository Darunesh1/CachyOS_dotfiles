# thunar

Only `uca.xml` is tracked -- Thunar's **custom actions**, the entries in its
right-click menu. `install.sh` links that one file, never the whole
`~/.config/Thunar/` directory: `accels.scm` lives beside it and Thunar rewrites
it whenever a keyboard shortcut changes.

Thunar also rewrites `uca.xml` itself whenever you edit custom actions in
*Edit -> Configure custom actions*. That means a `git diff` here after using
that dialog is expected, not a bug -- commit it.

## Why "Open Terminal Here" calls kitty directly

The action Thunar ships by default runs:

```
exo-open --working-directory %f --launch TerminalEmulator
```

which fails on this system with *"Failed to launch preferred application for
category TerminalEmulator -- could not find fallback TerminalEmulator
application"*. Nothing is wrong with kitty. `exo-open` hands that category to a
separate binary, `xfce4-mime-helper` (the string is in
`/usr/lib/libexo-2.so.0`), and it is **not installed**: in Xfce 4.20 the mime
helper moved out of `exo` into the `xfce4-settings` package. No `helpers.rc`
entry can fix that, because the program that would read it is missing.

So the action runs `kitty --working-directory %f` instead. Installing
`xfce4-settings` would also have worked, at the cost of ~54 MB once
`elementary-icon-theme`, `colord` and `gnome-themes-extra` come along with it --
not worth it for one menu entry.

**One thing this does not fix:** Thunar's *File menu* has its own built-in "Open
Terminal Here", hardcoded to the same `exo-open` call (`strings /usr/bin/thunar`
shows it), and that one still fails. Use the right-click entry.

## Archives

Handled by `xarchiver` plus `thunar-archive-plugin`, both in
`packages/pacman.txt`. The plugin adds **Extract Here** / **Create Archive** to
the right-click menu; the `xarchiver.tap` file that teaches the plugin how to
call xarchiver ships with xarchiver itself, not with the plugin.

Double-click is separate from the right-click menu: it needs xarchiver
registered as the default handler for each archive type. Stage 8 of `install.sh`
does that with `xdg-mime`, which writes `~/.config/mimeapps.list` -- per-user
state, so it is set by the installer rather than tracked as a file here.

xarchiver is a front end; the real work is done by command-line tools. `unzip`
only *extracts*, so `zip` is in the package list as well -- without it,
"Create Archive" cannot produce a `.zip`. `7z`, `tar`, `gzip`, `bzip2`, `xz`,
`zstd` and `unrar` are already present. Creating `.rar` needs the proprietary
`rar`, which is not installed and is not worth adding -- use `.7z` or `.zip`.
