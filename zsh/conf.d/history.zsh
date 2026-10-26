#!/usr/bin/env zsh

# History Configuration
#
# Why this file exists: conf.d/core.zsh sets HISTFILE, HISTSIZE and SAVEHIST and
# then stops. No history OPTION was set anywhere in this config, so every one of
# them sat at its zsh default. Measured on the live shell -- `setopt` prints only
# options that differ from the default, and it printed exactly one line,
# `autocd`. Cross-checked with `zsh -f`, which prints no history options either:
#
#     appendhistory    = ON   (zsh default)
#     sharehistory     = OFF
#     incappendhistory = OFF
#
# Two things followed from that, and together they are why the dim grey
# suggestion kept coming up empty for commands used every day:
#
#   1. Duplicates were never collapsed. ~/.config/zsh/.zsh_history held 1292
#      lines and 391 unique ones -- 70% repeats. `exit` alone was 147 entries,
#      `cls` 77, `..` 36. The suggestion pool was a third of its apparent size.
#
#   2. With SHARE_HISTORY off, a command is written only when its shell exits, so
#      nothing typed in one terminal can be suggested in another until that one
#      is closed. With five zsh processes running, the history file contained
#      ZERO docker, npm, pnpm, mvn or bat lines while a Maven JVM, a vite dev
#      server and eight Docker containers were up -- every one of those commands
#      had been typed in a tab that was still open. `docker <TAB-less prefix>`
#      suggesting nothing was not a bug in the strategy; the command had simply
#      never reached the file.
#
# A separate file rather than more lines in core.zsh: core.zsh is a fork of
# /usr/share/cachyos-zsh-config/cachyos-config.zsh (owned by cachyos-zsh-config
# 1.0.3-1, per `pacman -Qo`), and keeping it close to upstream is what makes it
# diffable when that package updates. conf.d/completion.zsh and
# conf.d/suggestions.zsh set the same precedent.
#
# LOAD ORDER: .zshenv sources conf.d/*.zsh in glob order --
#   binds -> completion -> core -> env -> history -> prompt -> suggestions
# so this runs AFTER core.zsh. That is required, not incidental: HISTSIZE below
# overrides the value core.zsh sets, and an earlier name would be overwritten by
# it.
#
# COST: setopt and three assignments. No forks, no command substitution.

# ── Sharing between terminals ───────────────────────────────────────────────
# The fix for problem 2 above. Per `man zshoptions`, SHARE_HISTORY "both imports
# new commands from the history file, and also causes your typed commands to be
# appended to the history file", and writes them with EXTENDED_HISTORY
# timestamps.
#
# Do NOT add inc_append_history or inc_append_history_time next to this. The man
# page is explicit that INC_APPEND_HISTORY "should be turned off if this option
# is in effect" and that the three are mutually exclusive.
#
# ACCEPTED DOWNSIDE: up-arrow and Ctrl-R now walk other terminals' commands too,
# which is the price of them being suggestable at all. The documented escape
# hatch is the `set-local-history` zle binding, if that ever becomes annoying in
# a particular shell.
setopt share_history

# ── Duplicates ──────────────────────────────────────────────────────────────
setopt hist_ignore_all_dups   # a repeated command removes the older copy, even
                              # when it is not the previous event -- this is what
                              # stops the 70% bloat growing back
setopt hist_find_no_dups      # Ctrl-R and up-arrow stop re-offering a line they
                              # have already shown
setopt hist_expire_dups_first # when the list has to be trimmed, lose a duplicate
                              # before losing a command seen only once

# HIST_EXPIRE_DUPS_FIRST needs headroom to work: the man page warns that it
# "will behave just like HIST_IGNORE_ALL_DUPS once the history fills up with
# unique events" unless HISTSIZE is larger than SAVEHIST. core.zsh sets both to
# 10000, so raise the in-memory size and leave the on-disk size alone.
HISTSIZE=20000

# ── Noise ───────────────────────────────────────────────────────────────────
setopt hist_ignore_space      # a leading space keeps a command out of history
setopt hist_reduce_blanks     # normalise whitespace before storing
setopt extended_history       # timestamp and duration per entry; share_history
                              # writes this format anyway, so this only makes it
                              # explicit
setopt hist_verify            # a history expansion (!!, !$) lands in the buffer
                              # to be looked at instead of executing immediately

# Commands that are pure noise in a suggestion: they are never worth recalling
# and they dominated the file (see the counts above). HISTORY_IGNORE keeps them
# out of the saved history; ZSH_AUTOSUGGEST_HISTORY_IGNORE keeps any that are
# already in there from being suggested.
#
# No code change is needed for the second one: the custom strategy in
# conf.d/suggestions.zsh already splices it into its search pattern, exactly as
# the stock history strategy does.
#
# The pattern is anchored by zsh itself -- it is matched against the whole line.
HISTORY_IGNORE='(exit|cls|clear|..|ls|pwd|btop|htop|z *)'
ZSH_AUTOSUGGEST_HISTORY_IGNORE=$HISTORY_IGNORE

export HISTSIZE HISTORY_IGNORE
