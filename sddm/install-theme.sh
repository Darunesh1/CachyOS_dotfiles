#!/usr/bin/env bash

# Install a qylock SDDM theme.
#
#   install-theme.sh [theme-name]        default: pixel-hollowknight
#   install-theme.sh --list              print the 39 theme names and exit
#
# qylock (https://github.com/Darkkal44/qylock) is a pack of SDDM themes, not a
# login manager of its own -- see sddm/README.md for what switching to SDDM
# involved.
#
# The repository is 1.13 GB: its git history is full of 4K videos. So this does
# a partial + sparse clone and pulls ONLY the chosen theme's files, which for
# pixel-hollowknight is about 39 MB. --filter=blob:none fetches no file contents
# until checkout, and the sparse path limits what checkout then asks for.
#
# This script deliberately does NOT enable sddm.service or disable greetd.
# Swapping the display manager is a separate, deliberate step -- get it wrong
# and the next boot has no login screen. install.sh stage 8 asks about it
# separately, and sddm/README.md has the rollback.

set -euo pipefail

REPO_URL="https://github.com/Darkkal44/qylock.git"
THEME="${1:-pixel-hollowknight}"
SELF_DIR="$(dirname "$(readlink -f "$0")")"
SYSTEM_THEMES="/usr/share/sddm/themes"
CONF_DIR="/etc/sddm.conf.d"

if [[ "$THEME" == "--list" ]]; then
    git ls-remote --heads "$REPO_URL" >/dev/null 2>&1 || { echo "no network" >&2; exit 1; }
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    git clone --filter=tree:0 --no-checkout --depth 1 "$REPO_URL" "$tmp" >/dev/null 2>&1
    git -C "$tmp" ls-tree --name-only HEAD themes/ | sed 's|themes/||'
    exit 0
fi

command -v sddm >/dev/null || {
    echo "install-theme: sddm is not installed. sudo pacman -S sddm gst-plugins-base gst-plugins-good" >&2
    exit 1
}

echo ":: fetching theme '$THEME' (sparse clone, not the full 1.13 GB repo)"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

git clone --filter=blob:none --no-checkout --depth 1 "$REPO_URL" "$tmp" >/dev/null
git -C "$tmp" sparse-checkout init --cone >/dev/null
git -C "$tmp" sparse-checkout set "themes/$THEME" >/dev/null
git -C "$tmp" checkout >/dev/null 2>&1

if [[ ! -d "$tmp/themes/$THEME" ]]; then
    echo "install-theme: no theme called '$THEME'. Try: $0 --list" >&2
    exit 1
fi

# A theme that needs a copyrighted font ships an empty font/ directory -- the
# README tells you to supply it yourself. pixel-hollowknight ships its own
# (PixelifySans), but say something rather than let the text silently fall back.
if [[ -d "$tmp/themes/$THEME/font" ]] \
   && ! compgen -G "$tmp/themes/$THEME/font/*.[to]tf" >/dev/null; then
    echo "!! '$THEME' expects a font in font/ and ships none -- see the qylock README."
fi

echo ":: installing to $SYSTEM_THEMES/$THEME  ($(du -sh "$tmp/themes/$THEME" | cut -f1))"
sudo mkdir -p "$SYSTEM_THEMES"
sudo rm -rf -- "${SYSTEM_THEMES:?}/$THEME"
sudo cp -r "$tmp/themes/$THEME" "$SYSTEM_THEMES/$THEME"

# 10- and 20- prefixes: SDDM reads /etc/sddm.conf.d in lexical order, and named
# files make it obvious which setting came from this repo.
sudo install -Dm644 "$SELF_DIR/theme.conf"          "$CONF_DIR/10-theme.conf"
sudo install -Dm644 "$SELF_DIR/virtualkeyboard.conf" "$CONF_DIR/20-virtualkeyboard.conf"

# The tracked theme.conf names a theme; if a different one was asked for on the
# command line, the installed copy has to agree or SDDM shows the old theme.
if [[ "$THEME" != "pixel-hollowknight" ]]; then
    sudo sed -i "s/^Current=.*/Current=$THEME/" "$CONF_DIR/10-theme.conf"
    echo ":: /etc/sddm.conf.d/10-theme.conf points at '$THEME' (repo copy still says pixel-hollowknight)"
fi

echo
echo "Installed. Nothing has switched yet -- greetd is still the login manager."
echo "Try it first, without switching:"
echo "    sddm-greeter-qt6 --test-mode --theme $SYSTEM_THEMES/$THEME"
echo "Then, only if it looks right:"
echo "    sudo systemctl disable greetd.service && sudo systemctl enable sddm.service && reboot"
echo "To undo from a text console (Ctrl+Alt+F2):"
echo "    sudo systemctl disable sddm && sudo systemctl enable greetd && sudo reboot"
