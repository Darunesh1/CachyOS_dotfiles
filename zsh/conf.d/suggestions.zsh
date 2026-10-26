#!/usr/bin/env zsh

# Autosuggestion Configuration
#
# Autosuggestions and completion are two different systems and it is worth being
# clear which is which, because they look similar on screen:
#
#   ~/Projects
#   > cd Projects        <- dim grey text: zsh-autosuggestions (this file)
#     ../  CGSMA/  ISP/  <- the popup: the completion system (completion.zsh)
#
# The popup is context-aware; it asks `_cd` what exists here. The dim suggestion
# was not: zsh-autosuggestions' stock `history` strategy returns the most recent
# history entry starting with what you typed, with no idea which directory you are
# standing in. So having once typed `cd Projects`, it offered it everywhere --
# including inside ~/Projects, where that directory does not exist.
#
# WHY THE `completion` STRATEGY IS GONE
# The plugin ships a `completion` strategy that asks the completion system
# instead, so it is context-aware by construction. It used to sit here as a last
# resort "for prefixes history has never seen". That was the wrong call and it
# has been removed. Re-measured by calling the strategy functions directly,
# 5 runs each:
#
#   prefix                 strategy      suggestion                   median
#   'cd '                  completion    cd ../                        8.1 ms
#   'hyprct'               completion    hyprctl                      14.3 ms
#   'docker comp'          completion    (nothing)                    82.4 ms
#   'git '                 completion    (nothing)                   150.9 ms
#   'sudo pacman -S fire'  completion    sudo pacman -S firecracker  303.0 ms
#   (every prefix)         valid_history as below                      0.0 ms
#
# The cost is paid PER KEYSTROKE, and only on prefixes history does not know --
# which is every command you have not typed before, i.e. exactly when it was
# supposed to help. 150 ms to return nothing for `git `, 303 ms to answer
# `firecracker`, which is just the alphabetically first match. `cd ../` is not a
# suggestion anyone wants either. It forks a zsh and a pty per fetch and caches
# nothing (src/strategies/completion.zsh:117-135).
#
# WHAT IS LOST: a command never typed before now gets no grey suggestion at all.
# TAB still completes it -- the completion system (conf.d/completion.zsh) is a
# different mechanism and is untouched by this.
#
# LOAD ORDER: this file must keep a name that sorts AFTER "core", because
# core.zsh is where ZSH_AUTOSUGGEST_STRATEGY used to be set and this file now
# owns it. The strategy function does not need to exist before the plugin loads --
# src/fetch.zsh dispatches it by name at fetch time, not at load time.

# ── Is this remembered command still runnable where we are standing? ────────
# Returns 0 (keep the suggestion) for anything it does not police. Only commands
# whose first argument must already exist are checked.
_myarch_suggestion_is_valid() {
    emulate -L zsh

    # (z) splits like the shell would, respecting quotes; (Q) then strips them.
    # Verified against: `cd "My Folder"` -> [My Folder], `cd -` -> [-],
    # `git commit -m "x y"` -> [commit].
    local -a words
    words=( ${(z)1} )
    local cmd=${words[1]} arg=${(Q)words[2]}

    case $cmd in
        (cd|pushd|nvim|vim|bat|cat|less) ;;
        (*) return 0 ;;   # not policed -- suggest it as before
    esac

    # Nothing to check: no argument, or the word is a flag. This is also what
    # lets `cd -` through, which is a real command and not a path.
    [[ -z $arg || $arg == -* ]] && return 0

    # ${(z)} leaves a leading tilde unexpanded, so do it by hand rather than
    # with ${~arg}, which would also glob and could match something unintended.
    local target=${arg/#\~/$HOME}

    case $cmd in
        (cd|pushd) [[ -d $target ]] ;;
        (*)        [[ -e $target ]] ;;
    esac
}

# ── history, filtered to what works here ────────────────────────────────────
# The contract for a custom strategy is undocumented upstream; it is only
# derivable from src/fetch.zsh:14-26, which loops the strategies in order, calls
# `_zsh_autosuggest_strategy_<name> "$buffer"`, and takes the first one to leave a
# non-empty global `suggestion`. fetch.zsh also discards any suggestion that does
# not start with the buffer, so this function does not need to check that itself.
_zsh_autosuggest_strategy_valid_history() {
    emulate -L zsh
    setopt EXTENDED_GLOB

    typeset -g suggestion=""

    # This escaping and the HISTORY_IGNORE splice are taken verbatim from the
    # stock history strategy (src/strategies/history.zsh:19-31) so that the two
    # behave identically everywhere they overlap. The (#m) flag is what makes
    # $MATCH available to the replacement.
    local prefix="${1//(#m)[\\*?[\]<>()|^~#]/\\$MATCH}"
    local pattern="$prefix*"
    if [[ -n $ZSH_AUTOSUGGEST_HISTORY_IGNORE ]]; then
        pattern="($pattern)~($ZSH_AUTOSUGGEST_HISTORY_IGNORE)"
    fi

    # Fast path. The newest match is almost always fine, and this is the same
    # single lookup the stock strategy does -- measured 0.11 ms over 888 entries.
    local newest="${history[(r)$pattern]}"
    if [[ -n $newest ]] && _myarch_suggestion_is_valid "$newest"; then
        typeset -g suggestion="$newest"
        return
    fi

    # Slow path, taken only when the newest match cannot work here: walk back for
    # one that can. (R) returns every match, most-recent-first -- verified by its
    # first element being identical to what (r) returns. Collecting all 171 `cd *`
    # matches out of 888 entries measured 0.37 ms, so this stays well under a
    # millisecond even when it fires.
    local m
    for m in "${(@)history[(R)$pattern]}"; do
        if _myarch_suggestion_is_valid "$m"; then
            typeset -g suggestion="$m"
            return
        fi
    done

    # Nothing in history works here. Leaving `suggestion` empty makes fetch.zsh
    # move on to the next strategy.
}

# One strategy, deliberately. Replaces core.zsh's old `(history completion)` and
# then this file's own `(valid_history completion)` -- see the block at the top
# for why the second name was dropped.
#
# A measurement worth keeping, because it is the one that says `valid_history`
# itself is not the thing that felt wrong: from $HOME against the real
# 1225-entry history, stock `history` and `valid_history` returned byte-identical
# suggestions for every prefix tried -- 'cd ', 'cd M', 'cd P', 'nvim ', 'cat ',
# 'git ', 'ls ', 'hyprctl ', 'pacman '. Where the suggestion was empty it was
# empty for both, because the command was missing from the history FILE, not
# filtered out here. conf.d/history.zsh is what fixes that.
ZSH_AUTOSUGGEST_STRATEGY=(valid_history)
