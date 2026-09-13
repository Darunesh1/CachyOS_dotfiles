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

# Uncomment to prevent searching for commands not found in package manager
# unset -f command_not_found_handler

# For Game Mode
if [ -f /tmp/game_mode_state ]; then
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
