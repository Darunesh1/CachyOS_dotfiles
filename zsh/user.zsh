# Source dynamic colors
[[ -f ~/.config/zsh/wallust-colors.zsh ]] && source ~/.config/zsh/wallust-colors.zsh

# Startup Commands
# Commands to execute on startup (before the prompt is shown)
if [[ $- == *i* ]]; then
    if command -v pokego >/dev/null; then
        pokego --no-title -r 1,3,6
    elif command -v pokemon-colorscripts >/dev/null; then
        pokemon-colorscripts --no-title -r 1,3,6
    elif command -v fastfetch >/dev/null; then
        if do_render "image"; then
            fastfetch --logo-type kitty
        fi
    fi
fi

alias gwine="gamemoderun wine"

# GitHub CLI. Its own name, `gh`, is taken by the alias gist's `git push`, so it
# answers to `gcli` here. `command` is required: without it zsh would expand the
# body's first word through that same alias and `gcli` would push.
alias gcli='command gh'

# Configuration Overrides
# ZSH_NO_PLUGINS=1      # Set to 1 to disable plugin loading
# ZSH_PROMPT=           # Unset to disable prompt customization
# ZSH_COMPINIT_CHECK=1  # Set compinit check interval (hours)
# ZSH_OMZ_DEFER=1       # Defer oh-my-zsh loading

if [[ ${ZSH_NO_PLUGINS} != "1" ]]; then
    # Oh-My-Zsh Plugins
    plugins=(
        "sudo"
    )
fi
