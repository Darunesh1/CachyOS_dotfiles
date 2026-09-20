# `gcli` is our name for the GitHub CLI (see user.zsh). Reuse the _gh completion
# the github-cli package installs, so it stays correct across gh updates.
(( $+functions[compdef] )) && compdef gcli=gh
