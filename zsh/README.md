# zsh

The load chain is order-sensitive and none of it is obvious from the filenames.

```
~/.zshenv -> zsh/.zshenv          sets ZDOTDIR=$HOME/.config/zsh
  └─ sources $ZDOTDIR/conf.d/*.zsh in GLOB order, not logical order:
       binds -> completion -> core -> env -> history -> prompt -> suggestions
          └─ core.zsh drives everything: compinit, plugins, aliases, and sources
             .zshrc LAST. history.zsh must sort AFTER it: it overrides HISTSIZE.
```

`~/.config/zsh` is a symlink to this directory, so `$ZDOTDIR` *is* the repo.
There is intentionally no `~/.zshrc`; `install.sh` removes one if it finds it,
because `$ZDOTDIR/.zshrc` is the real file and two would both load.

Two consequences of the glob order that are easy to trip over:

- `core.zsh` runs **before** `env.zsh`, so anything in `core.zsh` that needs
  `$XDG_*` must supply its own fallback.
- `completion.zsh` sorts before `core.zsh`. That is deliberate and must stay
  true: `zmodload zsh/complist` has to happen before `core.zsh` calls
  `compinit`. Renaming the file to something sorting after `core` would silently
  break the completion menu.

## Why completion.zsh exists

This config used to load oh-my-zsh, which quietly supplied a whole layer of
completion behaviour. Switching to zinit dropped all of it -- zinit is a plugin
manager and nothing else. What survived was one line:

```zsh
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
```

Case-insensitive matching, and nothing more. The completion *engine* was never
broken (`cd` resolved to `_cd`, `mv` to `_mv`, `pacman` to `_pacman` the whole
time) -- it simply had no rules, so `zsh-autosuggestions` was doing all the
visible work and completion felt like it was only replaying history.

`conf.d/completion.zsh` is that missing layer. Measured before and after:

| | before | after |
|---|---|---|
| `:completion:*` rules in effect | 5 (3 of them zinit's own) | 32 |
| `:fzf-tab:*` rules | 0 | 10 |
| `zsh/complist` module | not loaded | loaded |
| `complete_in_word` / `always_to_end` | off | on |
| `$LS_COLORS` | empty | 31 entries |
| startup, median of 10 | 160 ms | 131 ms |

The two behaviours that prompted it, both verified through a pseudo-terminal
against the real interactive shell:

```
cd <TAB>                 ->  ../  dir_a/  dir_b/        (no files at all)
mv file_x.txt <TAB>      ->  [directory] dir_a/ dir_b/
                             [file]      file_y.txt     (file_x.txt suppressed)
```

### `ignore-line`, and why it is scoped

Not re-offering a file already on the line is `ignore-line`, set to `other`
rather than `yes`, for an explicit list of commands:

```zsh
zstyle ':completion:*:(rm|mv|cp|ln|chmod|chown|kill|shred):*' ignore-line other
```

`yes` also excludes the word under the cursor, which breaks completing a prefix
shared with an already-typed name -- `rm foo<TAB>` would refuse to offer
`foo_important` once `foo` was on the line. `other` ignores every word *except*
the current one.

The command list is explicit because the zsh manual warns you almost certainly
do not want this on a general context such as `:completion:*`. It would sabotage
commands that legitimately take an argument twice, like `diff -u a a`.

Known upstream limitation, **not** verified against zsh 5.9.2: zsh-users reports
from 2004 and 2014 say `ignore-line` misses arguments containing spaces or glob
characters, so a file called `m (25).txt` may still be offered twice.

## TAB is owned by fzf-completion -- this is not a bug

`bindkey '^I'` reports `fzf-completion`, not `fzf-tab-complete`, because
`completions/fzf.zsh` runs `eval "$(fzf --zsh)"` after `plugin.zsh`. It looks
wrong and is fine: fzf captured the previous binding into
`fzf_default_completion=fzf-tab-complete`, so the `**` trigger goes to fzf's own
widget and every ordinary TAB falls through to fzf-tab. Leave it alone. If you
ever reorder those two, check `print $fzf_default_completion` still says
`fzf-tab-complete` -- if it says `expand-or-complete`, fzf-tab has been cut out
of the chain and all the styles above will render as a plain list.

`plugin.zsh` loads `fzf-tab` immediately before `zsh-autosuggestions` for a
separate reason: upstream requires it to load after `compinit` but before
anything that wraps ZLE widgets, which `zsh-autosuggestions` and
`fast-syntax-highlighting` both do. It used to sit at the end of the file, after
both.

## Keys inside the popup

| key | does |
|---|---|
| <kbd>Tab</kbd> | next candidate (wraps at the end) |
| <kbd>Shift</kbd>+<kbd>Tab</kbd> | previous candidate |
| <kbd>Enter</kbd> | select the highlighted one |
| <kbd>F1</kbd> / <kbd>F2</kbd> | switch between the `[directory]` and `[file]` groups |
| <kbd>Ctrl</kbd>+<kbd>/</kbd> | descend into the highlighted directory and keep completing |
| <kbd>Ctrl</kbd>+<kbd>Space</kbd> | select several |

Getting that means setting almost **nothing**, and the omissions are load-bearing:

```zsh
# correct -- do not "complete" this block from the README
zstyle ':fzf-tab:*' continuous-trigger 'ctrl-/'
zstyle ':fzf-tab:*' fzf-flags --height=40% --border=none --info=inline --cycle
```

`fzf-bindings` and `switch-group` are deliberately **unset**. fzf-tab already
defaults to `tab:down,btab:up,change:top,ctrl-space:toggle,...`
(`lib/-ftb-fzf:25`) and to F1/F2 for groups (`lib/-ftb-fzf:36`), which is exactly
the contract above.

The trap is that fzf-tab **appends** those two styles to its defaults rather than
replacing them (`lib/-ftb-fzf:31-32`), and fzf honours the *last* binding given for
a key. So the line fzf-tab's README shows as an example --

```zsh
zstyle ':fzf-tab:*' fzf-bindings 'tab:accept'      # don't
```

-- yields `--bind=tab:down,...,tab:accept`, and TAB stops meaning "next candidate"
and starts meaning "select". The popup then closes on the first entry every time,
which looks like completion guessing wrongly rather than a keybinding. That block in
the README is a menu of examples, not a recommended configuration; it was once
copied in whole and took three good defaults with it.

`continuous-trigger` is the opposite case and must be stated, not omitted: it
defaults to `/` (`fzf-tab.zsh:156`), so a slash cannot be typed into the filter --
which is the first thing you reach for when narrowing a list of paths. `ctrl-/`
keeps the behaviour on a key that never appears in a path. It is passed to fzf as
`--expect`, so if it ever stops working, check the terminal is still sending `0x1F`
for <kbd>Ctrl</kbd>+<kbd>/</kbd>; `alt-/` is the more reliably encoded fallback.

## Suggestions are not completion

Two different systems, and they look alike on screen, so it is worth fixing which
is which:

```
~/Projects
❯ cd Projects          <- dim grey: zsh-autosuggestions   (conf.d/suggestions.zsh)
  ../  CGSMA/  ISP/    <- the popup:  the completion system (conf.d/completion.zsh)
```

In that real screenshot the popup was correct and the dim text was wrong. The stock
`history` strategy returns the newest history entry starting with what you typed and
has no idea which directory you are in, so having once typed `cd Projects` it
offered it everywhere -- including inside `~/Projects`, where no such directory
exists.

### The completion strategy was tried as a fallback, and removed

The plugin ships a `completion` strategy which is context-aware by construction,
and it sat last in the list "for prefixes history has never seen". That was the
wrong call. Re-measured by calling the strategy functions directly, 5 runs each:

| prefix | strategy | suggestion | median |
|---|---|---|---|
| `cd ` | completion | `cd ../` | 8.1 ms |
| `hyprct` | completion | `hyprctl` | 14.3 ms |
| `docker comp` | completion | nothing | 82.4 ms |
| `git ` | **completion** | **nothing** | **150.9 ms** |
| `sudo pacman -S fire` | **completion** | **`sudo pacman -S firecracker`** | **303.0 ms** |
| any | `valid_history` | as below | **0.0 ms** |

The cost is per **keystroke**, and it is only paid on prefixes history does not
know — which is exactly a command you have not typed before, the case it was
supposed to serve. 150 ms to answer nothing; 303 ms to answer `firecracker`,
which is only the alphabetically first match. It forks a zsh and a pty per fetch
and caches nothing (`src/strategies/completion.zsh:117-135`).

`ZSH_AUTOSUGGEST_STRATEGY` is now `(valid_history)` alone. What is lost: a
command never typed before gets no grey suggestion. TAB still completes it —
that is the completion system, a different mechanism.

### The custom strategy

`conf.d/suggestions.zsh` defines `valid_history`: the same history lookup, then a
check that the command can actually run here. `cd`, `pushd`, `nvim`, `vim`, `bat`,
`cat` and `less` are policed; everything else is passed through untouched. When the
newest match fails the check it walks further back for one that passes, so in
`~/Projects` you get `cd CGSMA` rather than nothing.

Measured: 0.17 ms on the fast path, 0.54 ms when it has to walk back, against
0.12 ms for the stock strategy. Shell startup is unchanged (A/B with the file moved
aside: 272.7 ms without, 268.4 ms with).

**Accepted downside:** `nvim newfile.md` is withheld, because the file does not
exist yet. That was a deliberate choice -- policing file arguments catches stale
suggestions more often than it blocks wanted ones. Narrow it by removing the editors
from the `case` in `_myarch_suggestion_is_valid`.

The custom-strategy contract is **undocumented upstream** and only derivable from
`src/fetch.zsh:14-26`: define `_zsh_autosuggest_strategy_<name>`, read the buffer
from `$1`, assign to a global `suggestion`, leave it empty to fall through. That
loop also discards any suggestion not starting with the buffer, so a strategy need
not check that itself.

## The suggestion pool -- conf.d/history.zsh

A later complaint that suggestions were "wrong or missing" turned out not to be
the strategy at all. Measured from `$HOME` against the real 1,225-entry history,
`valid_history` and the stock `history` strategy returned **identical**
suggestions for every prefix tried (`cd `, `cd M`, `cd P`, `nvim `, `cat `,
`git `, `ls `, `hyprctl `, `pacman `). Where one was empty, both were — because
the command was missing from the history *file*.

`core.zsh` set `HISTFILE`, `HISTSIZE` and `SAVEHIST` and no history **option**.
The live shell's `setopt`, which prints only non-default options, printed exactly
one line: `autocd`. So:

| | before | after |
|---|---|---|
| history file | 1292 lines / **391 unique** | 402 lines / **343 unique entries** |
| `exit` entries | 147 | 0 (in `HISTORY_IGNORE`) |
| commands from other terminals | invisible until that shell exits | imported at each prompt |

The second row is the one that mattered. With five zsh processes running, the
history file contained **zero** `docker`, `npm`, `pnpm`, `mvn` or `bat` lines
while a Maven JVM, a vite dev server and eight Docker containers were up — every
one of those had been typed in a tab that never closed. `setopt share_history`
fixes that; `man zshoptions` is explicit that `INC_APPEND_HISTORY` must then stay
off, and that the three append options are mutually exclusive.

**Accepted downside:** up-arrow and Ctrl-R now walk other terminals' commands
too. The documented escape hatch is the `set-local-history` zle binding.

`HIST_EXPIRE_DUPS_FIRST` needs `HISTSIZE` > `SAVEHIST` or the man page says it
degrades to `HIST_IGNORE_ALL_DUPS`, so `history.zsh` raises `HISTSIZE` to 20000
and leaves `SAVEHIST` at 10000.

### If you ever dedupe the history file by hand, do not do it per line

A plain-format zsh history stores a multi-line command as several physical lines,
the inner ones ending in `\`. The file had **66** such lines. A line-based
`awk`/`sort -u` dedupe silently destroyed every multi-line entry in it — 15
commands, including two `rsync`/`sudo install` invocations — because it kept the
last copy of a shared continuation line and orphaned its parent.

Use zsh's own parser (`fc -R`, then walk `$history`), dedupe whole entries, and
write back in extended format escaping each embedded newline as backslash +
newline. Then verify by re-reading the file and diffing the entry set against a
backup. One harness quirk to expect while verifying: `fc -R` inside a
non-interactive `zsh -f` script drops the file's **final** entry, so a count that
is short by exactly one is the harness, not data loss.

## Previews are deliberately a short list

Every fzf-tab preview spawns a process on each TAB. On an 8 GB machine that is
not free, so previews are configured for browsing-shaped commands only -- `cd`,
`ls`/`eza`/`tree`, the editors and pagers, `systemctl`, `kill` -- and not as a
blanket `:fzf-tab:*` rule.

`eza` needs `--icons=always`. A bare `--icons` consumes the next argument as its
value and errors out.

## Known redundancies, left alone

Not bugs, but worth knowing before you debug something odd:

- Three overlapping history plugins are loaded: `zsh-autosuggestions`,
  `zsh-history-substring-search` and `history-search-multi-word`.
- `_load_compinit` is called twice -- `core.zsh:156` at top level, and again
  inside `_defer_omz_after_prompt_before_input` (`core.zsh:44`), which only runs
  on the oh-my-zsh deferred path that this setup does not take.
- `zsh-completions` is installed both as a pacman package and as a zinit plugin.
  The zinit copy is the one in `$fpath`.

## Changing things

| change | what to do |
|---|---|
| a completion style | edit `conf.d/completion.zsh`, open a new shell |
| completion feels stale after an edit | `rm $ZDOTDIR/.zcompdump`, open a new shell |
| a slow completion is cached wrongly | `rm -rf ~/.cache/zsh/zcompcache` |
| your own aliases and overrides | `user.zsh` -- it is sourced before plugins load |
| a plugin | `plugin.zsh`, minding the fzf-tab ordering note above |

Do not add completion `zstyle`s to `conf.d/core.zsh`. It loads after
`completion.zsh`, so anything there silently wins.

`wallust-colors.zsh` is generated from `wallust/templates/zsh.zsh` and is
gitignored, as are `.zcompdump` and `.zsh_history`.
