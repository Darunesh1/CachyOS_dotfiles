#!/usr/bin/env zsh

export ZDOTDIR="$HOME/.config/zsh"

# Load all configuration files from conf.d/
for file in "$ZDOTDIR/conf.d/"*.zsh; do
    [ -r "$file" ] && source "$file"
done
