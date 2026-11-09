---
status: "accepted"
date: 2026-11-03
decision-makers: darriour
---

# Drop the `completion` zsh-autosuggest strategy

## Context and Problem Statement

Typing stuttered at the start of unfamiliar commands, and the grey inline
suggestion often offered nothing. `ZSH_AUTOSUGGEST_STRATEGY` was
`(valid_history completion)`, with a comment arguing that `completion` was
worth keeping as a fallback for prefixes history had never seen.

## Decision Drivers

* The strategy runs **per keystroke**, so its cost is paid while typing.
* The fallback fires on exactly the prefixes history does not know, which is
  every new command.
* 8 GB Intel-iGPU laptop; the shell must not be where latency comes from.

## Considered Options

* Keep `completion` last, as a fallback.
* Put `completion` first.
* Remove `completion` and run `valid_history` alone.

## Decision Outcome

Chosen option: **remove `completion`**. Re-measured on the current binary, five
runs each:

```
completion  'git '                  median 150.9 ms  max 161.2 ms  -> []
completion  'sudo pacman -S fire'   median 303.0 ms  max 312.3 ms  -> [sudo pacman -S firecracker]
completion  'docker comp'           median  82.4 ms  max  97.6 ms  -> []
completion  'cd '                   median   8.1 ms  max  16.6 ms  -> [cd ../]
valid_hist  (every prefix)          median   0.0 ms
```

150 ms to return nothing for `git `, and where it does answer it answers the
alphabetically first match (`firecracker`) or `cd ../`. This reverses a
decision made in `205da56`, which was wrong.

`valid_history` was separately exonerated: measured against the real
1,225-entry history it returns byte-identical suggestions to the stock
`history` strategy for every prefix tried. The real complaint was a starved
pool — 1,292 lines holding only 391 unique ones, and no `SHARE_HISTORY`, so
commands typed in one tab were invisible to every other.

### Consequences

* Good, because per-keystroke latency drops to ~0 ms.
* Bad, because a command never typed before now gets no grey suggestion. TAB
  still completes it — the completion system is a separate mechanism and is
  untouched.

### Confirmation

```sh
zsh -ic 'typeset -p ZSH_AUTOSUGGEST_STRATEGY'
# -> typeset -a ZSH_AUTOSUGGEST_STRATEGY=( valid_history )
```

`./install.sh --check` carries a `suggestions` row that WARNs if the
`completion` strategy returns.

## More Information

The pool fix (`share_history`, `hist_ignore_all_dups`, the noise filter) and
the measurements behind it are in [../zsh/README.md](../zsh/README.md).
Commit `ef03e74`.
