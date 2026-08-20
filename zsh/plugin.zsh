# Plugin Configuration
# Uses Zinit plugin manager for fast, flexible plugin loading

# ================================================================
# Zinit Plugin Manager Setup
# ================================================================

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# Plugin: history-search-multi-word
zinit load zdharma-continuum/history-search-multi-word

# Plugin: zsh-autosuggestions
zinit light zsh-users/zsh-autosuggestions

# Plugin: fast-syntax-highlighting
zinit light zdharma-continuum/fast-syntax-highlighting

# Snippet: Useful Zsh functions
zinit snippet https://gist.githubusercontent.com/hightemp/5071909/raw/

# Plugin: z (directory jumper)
zinit light rupa/z

# Plugin: zsh-completions
zinit light zsh-users/zsh-completions

# Plugin: zsh-history-substring-search
zinit light zsh-users/zsh-history-substring-search

# Snippet: Oh My Zsh git plugin
zinit snippet https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/git/git.plugin.zsh

# Plugin: zsh-autopair
zinit light hlissner/zsh-autopair

# Plugin: fzf-tab
zinit light Aloxaf/fzf-tab

# Plugin: alias-tips
zinit light djui/alias-tips
