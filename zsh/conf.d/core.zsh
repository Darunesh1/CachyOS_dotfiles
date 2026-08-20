#!/usr/bin/env zsh

# Core Zsh Configuration
# This file is sourced by ZSH on startup
# Provides plugin loading, functions, completions, and aliases

function _load_functions() {
    # Load all custom function files
    for file in "${ZDOTDIR:-$HOME/.config/zsh}/functions/"*.zsh; do
        [ -r "$file" ] && source "$file"
    done
}

function _load_completions() {
    for file in "${ZDOTDIR:-$HOME/.config/zsh}/completions/"*.zsh; do
        [ -r "$file" ] && source "$file"
    done
}

function _dedup_zsh_plugins {
    unset -f _dedup_zsh_plugins
    # Oh-my-zsh installation path
    zsh_paths=(
        "/usr/share/oh-my-zsh"
        "/usr/local/share/oh-my-zsh"
        "$HOME/.oh-my-zsh"
    )
    for zsh_path in "${zsh_paths[@]}"; do [[ -d $zsh_path ]] && export ZSH=$zsh_path && break; done
    # Load default plugins
    local default_plugins=(git zsh-256color zsh-autosuggestions zsh-syntax-highlighting)
    plugins+=("${plugins[@]}" "${default_plugins[@]}")
    # Deduplicate plugins
    plugins=("${(@u)plugins}")
    # Defer oh-my-zsh loading until after prompt appears
    typeset -g DEFER_OMZ_LOAD=1
}

function _defer_omz_after_prompt_before_input() {
    [[ -r $ZSH/oh-my-zsh.sh ]] && source $ZSH/oh-my-zsh.sh

    # Add completions directory to fpath
    fpath=($ZDOTDIR/completions "${fpath[@]}")

    _load_compinit
    _load_functions
    _load_completions

    # zsh-autosuggestions won't work on first prompt when deferred
    if typeset -f _zsh_autosuggest_start >/dev/null; then
        _zsh_autosuggest_start
    fi

    chmod +r $ZDOTDIR/.zshrc
    [[ -r $ZDOTDIR/.zshrc ]] && source $ZDOTDIR/.zshrc
}

function _load_deferred_plugin_system() {
    # Exit early if ZSH_DEFER is not set to 1
    if [[ "${ZSH_DEFER}" != "1" ]]; then
        unset -f _load_deferred_plugin_system
        return
    fi

    # Defer oh-my-zsh loading until after prompt appears
    if [[ -n $DEFER_OMZ_LOAD ]]; then
        unset DEFER_OMZ_LOAD
        [[ ${VSCODE_INJECTION} == 1 ]] || chmod -r $ZDOTDIR/.zshrc
        zle -N zle-line-init _defer_omz_after_prompt_before_input
    fi

    # zsh-autosuggestions won't work on first prompt when deferred
    if typeset -f _zsh_autosuggest_start >/dev/null; then
        _zsh_autosuggest_start
    fi

    # Some binds won't work on first prompt when deferred
    bindkey '\e[H' beginning-of-line
    bindkey '\e[F' end-of-line
}

function do_render {
    local type="${1:-image}"
    TERMINAL_IMAGE_SUPPORT=(kitty konsole ghostty WezTerm)
    local terminal_no_art=(vscode code codium)
    TERMINAL_NO_ART="${TERMINAL_NO_ART:-${terminal_no_art[@]}}"
    CURRENT_TERMINAL="${TERM_PROGRAM:-$(ps -o comm= -p $(ps -o ppid= -p $$))}"

    case "${type}" in
    image)
        [[ " ${TERMINAL_IMAGE_SUPPORT[@]} " =~ " ${CURRENT_TERMINAL} " ]] && return 0 || return 1
        ;;
    art)
        [[ " ${TERMINAL_NO_ART[@]} " =~ " ${CURRENT_TERMINAL} " ]] && return 1 || return 0
        ;;
    *)
        return 1
        ;;
    esac
}

function _load_compinit() {
    autoload -Uz compinit

    # Use cached completions if still valid (within ZSH_COMPINIT_CHECK hours)
    local dumpfile=${ZDOTDIR}/.zcompdump
    local check_hours=${ZSH_COMPINIT_CHECK:-24}
    if [[ -f $dumpfile ]] && [[ -n $(find $dumpfile -mmin -$((check_hours * 60)) 2>/dev/null) ]]; then
        compinit -C
    else
        compinit
    fi

    _comp_options+=(globdots)
}

function _load_prompt() {
    source ${ZDOTDIR}/prompt.zsh 2>/dev/null || source ${ZDOTDIR}/conf.d/prompt.zsh 2>/dev/null
}

# Configuration Variables
ZSH_DEFER="1"           # Unset in user.zsh to disable deferred loading
ZSH_PROMPT="1"          # Unset in user.zsh to disable prompt customization
ZSH_NO_PLUGINS="0"      # Set to "1" in user.zsh to disable plugin loading
ZSH_COMPINIT_CHECK="24" # Hours between compinit security checks

ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# History configuration
HISTFILE=${HISTFILE:-$ZDOTDIR/.zsh_history}
if [[ -f $HOME/.zsh_history ]] && [[ ! -f $HISTFILE ]]; then
    echo "Please manually move $HOME/.zsh_history to $HISTFILE"
fi
HISTSIZE=10000
SAVEHIST=10000

export HISTFILE ZSH_AUTOSUGGEST_STRATEGY HISTSIZE SAVEHIST

# Package Manager Configuration
PM_COMMAND=(yay)

# Load user configuration
if [[ -f $HOME/.user.zsh ]]; then
    source $HOME/.user.zsh
elif [[ -f $ZDOTDIR/user.zsh ]]; then
    source $ZDOTDIR/user.zsh
fi

_load_compinit

if [[ ${ZSH_NO_PLUGINS} != "1" ]]; then
    _dedup_zsh_plugins
    if [[ "$ZSH_OMZ_DEFER" == "1" ]] && [[ -r $ZSH/oh-my-zsh.sh ]]; then
        _load_deferred_plugin_system
        _load_prompt
    # The condition sources the file, so do NOT source it again in the body --
    # that loaded every zinit plugin twice on each interactive shell.
    elif [[ -r $ZDOTDIR/plugin.zsh ]] && source $ZDOTDIR/plugin.zsh; then
        _load_prompt
        _load_functions
        _load_completions
    elif [[ -r $ZSH/oh-my-zsh.sh ]]; then
        source $ZSH/oh-my-zsh.sh
        _load_prompt
        _load_functions
        _load_completions
    else
        echo "No plugin system found. Please install a plugin system or create a $ZDOTDIR/plugin.zsh file."
    fi
else
    [[ -r $ZDOTDIR/plugin.zsh ]] && source $ZDOTDIR/plugin.zsh
    _load_prompt
    _load_functions
    _load_completions
fi

__package_manager () {
    ${PM_COMMAND[@]} "$@"
}

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
# Aliases
alias cls='clear' \
    in='__package_manager -S' \
    un='__package_manager -Rns' \
    up='__package_manager -Syu' \
    pl='__package_manager -Qs' \
    pa='__package_manager -Ss' \
    vc='code' \
    fastfetch='fastfetch --logo-type kitty' \
    ..='cd ..' \
    ...='cd ../..' \
    .3='cd ../../..' \
    .4='cd ../../../..' \
    .5='cd ../../../../..' \
    mkdir='mkdir -p'
