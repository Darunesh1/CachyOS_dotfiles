# User Configuration
# Add your custom configurations here

# Editor
# Was `code`, which is not installed on this machine -- so sudoedit,
# `systemctl edit`, `crontab -e` and less's `v` all failed. git escaped it only
# because core.editor is set separately.
export EDITOR=nvim
export VISUAL=$EDITOR
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Typing a directory name cds into it (`../Documents`, `~/Downloads`).
# oh-my-zsh used to set this; this config loads zinit instead, which does not.
setopt auto_cd

# Uncomment to prevent searching for commands not found in package manager
# unset -f command_not_found_handler

# For Game Mode
if [ -f "${XDG_RUNTIME_DIR:-/tmp}/game-mode/active" ]; then
    export MESA_GLTHREAD=true
    export MESA_NO_ERROR=1
fi

# pnpm
# Two `pnpm setup` runs had each appended a block, and they disagreed: one added
# $PNPM_HOME, the other $PNPM_HOME/bin. The binaries live in bin/, so that is the
# one that matters.
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

. "$HOME/.local/share/../bin/env"

# npm's user prefix. Holds kilo, kilocode and omniroute -- installed with npm,
# so no package owns them (`pacman -Qo` errors on all three) and no manifest in
# packages/ can install them. Without this line those three are not on PATH.
export PATH="$HOME/.local/npm/bin:$PATH"

# There was an `export PATH=/home/darriour/.opencode/bin:$PATH` here. Removed
# on 2026-11-09: opencode is a pacman package (opencode 2.2.5-1.1) and already
# ships /usr/bin/opencode, so that line put a stale hand-installed 240 MB copy
# ahead of the 252 MB one pacman keeps updated -- `command -v opencode`
# resolved to the home copy. Two installs with PATH order picking the winner.
# If the hand-installed build is ever wanted instead, remove the package
# (`pacman -Rns opencode`) so there is exactly one owner.
