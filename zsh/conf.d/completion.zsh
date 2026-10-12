#!/usr/bin/env zsh

# Completion Configuration
#
# Why this file exists at all:
#
# This config used to load oh-my-zsh, which quietly supplied a whole set of
# completion styles -- grouped menus, coloured lists, directory-only `cd`,
# case-insensitive matching with fallbacks. Switching to zinit dropped every one
# of them, because zinit is a plugin manager and nothing more. The same
# regression is already documented for `auto_cd` in .zshrc. What was left behind
# was a single line in conf.d/core.zsh:
#
#     zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
#
# That is case-insensitivity and nothing else, which is why completion felt like
# it was only guessing from history: zsh-autosuggestions was doing all the
# visible work while the actual completion system sat unconfigured. The engine
# was never broken -- `cd` already resolved to `_cd`, `mv` to `_mv`, `git` to
# `_git` -- it just had no rules to follow. That matcher-list line now lives
# below instead, widened.
#
# LOAD ORDER -- this file must keep a name that sorts before "core":
# .zshenv sources conf.d/*.zsh in glob order, which is
#   binds -> completion -> core -> env -> prompt
# so this runs BEFORE core.zsh's compinit. That is required, not incidental:
# `zmodload zsh/complist` has to happen before compinit or the menu widgets are
# never redefined. zstyle and setopt do not care about order, since styles are
# read at completion time.
#
# COST: this file contains no command substitutions and no subshells, so it adds
# nothing measurable to shell startup. Keep it that way -- it is the reason
# LS_COLORS below is a literal string rather than $(dircolors -b).

# ── The complist module ─────────────────────────────────────────────────────
# Must precede compinit. Provides the coloured, navigable completion list.
zmodload -i zsh/complist

# ── Shell options ───────────────────────────────────────────────────────────
setopt complete_in_word     # TAB in the middle of a word completes there instead
                            # of jumping to the end first
setopt always_to_end        # ... but once a completion is inserted, put the
                            # cursor after it
setopt auto_param_slash     # completing a directory appends /, so the next TAB
                            # descends into it
setopt list_packed          # pack the candidate list into fewer rows; on a
                            # laptop screen a long /usr/bin listing otherwise
                            # scrolls the prompt away
setopt path_dirs            # complete commands found in subdirectories of $PATH
unsetopt menu_complete      # Deliberate. menu_complete makes TAB silently insert
                            # the first candidate rather than showing the list,
                            # which is exactly the "it is not even trying"
                            # behaviour this file is meant to fix.
unsetopt flow_control       # frees ^S/^Q, which otherwise freeze the terminal

# ── Which completers run, and in what order ─────────────────────────────────
# Each is tried only if the previous one found nothing, so the expensive one
# costs nothing on a normal completion.
#   _complete     exact and prefix matches -- the usual case
#   _match        treat the word as a glob pattern (`ls *.ts<TAB>`)
#   _approximate  allow typos: `cd ~/Doenlo<TAB>` still finds Downloads/
zstyle ':completion:*' completer _complete _match _approximate

# One mistake allowed, no more. "numeric" means a literal count rather than a
# proportion of the word length, so a long path does not quietly permit three
# errors and offer something unrelated.
zstyle ':completion:*:approximate:*' max-errors 1 numeric
zstyle ':completion:*:match:*' original only

# ── How a typed word is matched against candidates ──────────────────────────
# Four stages, tried in order, each looser than the last:
#   1. ''                        exact
#   2. m:{a-zA-Z}={A-Za-z}       case-insensitive  (this is the rule that used
#                                to be the entire completion config)
#   3. r:|=*  l:|=* r:|=*        partial words: `n-i<TAB>` -> `nvim-install`
#   4. ...r:|=**                 substring: `grid<TAB>` -> `waybar-grid-layout`
zstyle ':completion:*' matcher-list '' \
    'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=* r:|=*' \
    'l:|=* r:|=*'

# ── Grouped, labelled, coloured output ──────────────────────────────────────
# Without group-name every candidate lands in one undifferentiated blob. With
# it, files, directories, options and arguments are listed under their own
# headings -- the single biggest readability win here.
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-dirs-first true
zstyle ':completion:*' verbose true
zstyle ':completion:*:descriptions' format '%F{blue}%B %d%b%f'
zstyle ':completion:*:messages'     format '%F{yellow} %d%f'
zstyle ':completion:*:warnings'     format '%F{red} no matches for %d%f'
zstyle ':completion:*:corrections'  format '%F{yellow} %d%f %F{red}(errors: %e)%f'
zstyle ':completion:*' select-prompt '%F{cyan}scrolling: %p%f'

# LS_COLORS is not set anywhere in this config and is empty by default, so the
# usual `list-colors ${(s.:.)LS_COLORS}` idiom silently colours nothing. Set it
# here as a literal -- `$(dircolors -b)` would mean a fork on every shell start
# for a value that never changes. Exported so GNU ls, tree and grep use it too;
# eza carries its own palette and ignores it.
export LS_COLORS='di=1;34:ln=1;36:so=1;35:pi=33:ex=1;32:bd=1;33:cd=1;33:su=1;31:sg=1;31:tw=1;34:ow=1;34:or=1;31:mi=1;31:*.tar=1;31:*.gz=1;31:*.zip=1;31:*.zst=1;31:*.jpg=1;35:*.png=1;35:*.svg=1;35:*.mp4=1;35:*.mkv=1;35:*.pdf=1;35:*.md=1;37:*.zsh=1;32:*.sh=1;32:*.lua=1;32:*.py=1;32:*.conf=33:*.toml=33:*.json=33'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# ── `cd` offers directories and nothing else ────────────────────────────────
# tag-order is what restricts the candidate set: local directories first, then
# the directory stack, then $cdpath entries. Plain files never appear.
zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
zstyle ':completion:*:*:cd:*' group-order local-directories directory-stack
# Scoped to the directory-changing commands. Set on ':completion:*' it also
# injects ./ and ../ into the *file* group of `mv`/`rm`, which is just noise.
zstyle ':completion:*:(cd|pushd|rmdir|mkdir):*' special-dirs true
zstyle ':completion:*' squeeze-slashes true   # `cd ~//Doc<TAB>` behaves sanely
zstyle ':completion:*:cd:*' ignore-parents parent pwd  # never offer the dir you
                                                       # are already standing in

# ── Do not re-offer a file already on the command line ──────────────────────
# `mv file_x.txt <TAB>` should not suggest file_x.txt again.
#
# Two deliberate choices. First, the value is `other`, not `yes`: `yes` also
# excludes the word under the cursor, which breaks completing a prefix shared
# with something already typed (`rm foo<TAB>` would refuse to complete
# foo_important when foo is already on the line). `other` ignores every word
# except the current one. Second, the scope is an explicit command list, because
# the zsh manual warns you almost certainly do not want this on a general
# context such as :completion:* -- it would sabotage commands that legitimately
# take the same argument twice, like `diff -u a a`.
#
# Known upstream limitation, not verified against zsh 5.9.2: zsh-users reports
# from 2004 and 2014 say ignore-line misses arguments containing spaces or glob
# characters, so a file called "m (25).txt" may still be offered twice.
zstyle ':completion:*:(rm|mv|cp|ln|chmod|chown|kill|shred):*' ignore-line other

# ── Caching for completers that shell out ───────────────────────────────────
# pacman and yay enumerate the whole repo database to build their candidate
# list; systemctl lists every unit. Cache the result instead of paying for it on
# every TAB.
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"
# Guarded so the common case (directory already there) costs no fork.
[[ -d ${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache ]] \
    || mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

# ── Nicer candidates for specific commands ──────────────────────────────────
zstyle ':completion:*:*:*:*:processes' command 'ps -u $USER -o pid,user,comm -w'
zstyle ':completion:*:(ssh|scp|sftp|rsync):*' tag-order 'hosts:-host:host hosts:-domain:domain'
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.*' insert-sections true
# Stop completion offering the useless pseudo-users that fill /etc/passwd.
zstyle ':completion:*:*:*:users' ignored-patterns \
    adm bin daemon ftp halt mail nobody operator shutdown sync systemd-'*' \
    dbus avahi colord cups geoclue nm-openvpn polkitd rtkit usbmux uuidd

# ── fzf-tab ─────────────────────────────────────────────────────────────────
# fzf-tab is loaded by plugin.zsh and was previously given no configuration at
# all, which is why it appeared to do nothing. It does not generate candidates
# itself -- it only renders whatever the styles above produce.
#
# `menu no` is required by fzf-tab, not a preference: with a menu style set it
# cannot capture the unambiguous prefix and misbehaves.
zstyle ':completion:*' menu no

zstyle ':fzf-tab:*' switch-group '<' '>'       # move between the group headings
zstyle ':fzf-tab:*' continuous-trigger '/'     # keep descending without re-TAB
zstyle ':fzf-tab:*' fzf-bindings 'tab:accept'
zstyle ':fzf-tab:*' fzf-flags --height=40% --border=none --info=inline
# NOT enabling use-fzf-default-opts: upstream warns some FZF_DEFAULT_OPTS flags
# break the plugin outright (Aloxaf/fzf-tab issue #455).

# Previews are kept to a short list of commands on purpose. Each TAB with a
# preview spawns a process, and this is a 7.6 GB machine -- a preview on every
# completion context would be a cost paid constantly for a benefit that only
# matters when browsing.
#
# eza here needs --icons=always: in eza 0.23 a bare --icons consumes the next
# argument as its value and errors out.
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons=always $realpath'
zstyle ':fzf-tab:complete:(ls|eza|tree|du|rmdir):*' fzf-preview 'eza -1 --color=always --icons=always $realpath'
zstyle ':fzf-tab:complete:(nvim|vim|bat|cat|less|nano|rm|mv|cp):*' fzf-preview \
    '[[ -d $realpath ]] && eza -1 --color=always --icons=always $realpath \
     || bat --color=always --style=numbers --line-range=:60 $realpath 2>/dev/null'
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview 'ps --pid=$word -o cmd --no-headers -w -w'
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' \
    fzf-preview 'eval echo \${(P)word}'
