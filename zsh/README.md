# zsh

The load chain is order-sensitive and none of it is obvious from the filenames.

```
~/.zshenv -> zsh/.zshenv          sets ZDOTDIR=$HOME/.config/zsh
  └─ sources $ZDOTDIR/conf.d/*.zsh in GLOB order, not logical order:
       binds.zsh  ->  completion.zsh  ->  core.zsh  ->  env.zsh  ->  prompt.zsh
          └─ core.zsh drives everything: compinit, plugins, history, aliases,
             and sources .zshrc LAST
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
