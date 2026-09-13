#!/usr/bin/env bash
#
# MyArch installer -- takes a fresh Arch + Hyprland box to a working setup.
#
# Every stage asks first and can be skipped. Stages are idempotent: re-running
# detects existing correct state and reports it rather than redoing the work.
#
#   ./install.sh              interactive install
#   ./install.sh --check      audit only, change nothing
#   ./install.sh --dry-run    print what would happen, change nothing
#   ./install.sh --yes        accept every prompt
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.config-backup-$TIMESTAMP"

ASSUME_YES=0
DRY_RUN=0
CHECK_ONLY=0

# Filled in as we go, read by the stage 10 summary.
BACKUP_MADE=0
SKIPPED_STAGES=()
SKIPWORKTREE_FILES=()

# ═══════════════════════════════════════════════════════════════════════════
# Output helpers
# ═══════════════════════════════════════════════════════════════════════════

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
    C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
fi

step() { printf '\n%s══ %s ══%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '  %s·%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
note() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
die()  { err "$*"; exit 1; }

# ask <prompt> [default]   default is "y" (Y/n) or "n" (y/N)
ask() {
    local prompt="$1" default="${2:-y}" hint reply
    [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"

    if (( ASSUME_YES )); then
        printf '  %s?%s %s %s %sy (--yes)%s\n' \
            "$C_YELLOW" "$C_RESET" "$prompt" "$hint" "$C_DIM" "$C_RESET"
        return 0
    fi
    # No tty to read from (piped into bash): fall back to the default.
    if [[ ! -t 0 ]]; then
        printf '  %s?%s %s %s %s%s (no tty)%s\n' \
            "$C_YELLOW" "$C_RESET" "$prompt" "$hint" "$C_DIM" "$default" "$C_RESET"
        [[ "$default" == "y" ]]
        return
    fi

    while true; do
        printf '  %s?%s %s %s ' "$C_YELLOW" "$C_RESET" "$prompt" "$hint"
        read -r reply || { echo; return 1; }
        reply="${reply:-$default}"
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     warn "Please answer y or n." ;;
        esac
    done
}

# run <cmd...>  -- the single choke point for everything that mutates the system
run() {
    if (( DRY_RUN )); then
        printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
        return 0
    fi
    "$@"
}

# Same, for things that need a shell (redirections, pipelines).
run_sh() {
    if (( DRY_RUN )); then
        printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
        return 0
    fi
    bash -c "$*"
}

skip_stage() { SKIPPED_STAGES+=("$1"); info "Skipped."; }

# Read a package manifest: strip comments, blanks and trailing comments.
read_manifest() {
    sed -E 's/[[:space:]]*#.*$//; /^[[:space:]]*$/d; s/^[[:space:]]+|[[:space:]]+$//g' "$1"
}

usage() {
    cat <<'USAGE'
MyArch installer

Usage: ./install.sh [OPTIONS]

Options:
  --check      Run only the final audit (stage 10) and exit. Changes nothing.
               Exits non-zero if anything is missing, so it works in a
               one-liner. Use this later to diagnose a broken setup.
  --dry-run    Print every command that would mutate the system, run none.
  --yes, -y    Accept every prompt. Implies --noconfirm for pacman.
  --help, -h   This message.

Stages (each is prompted and skippable):
   1. Packages          official repo packages from packages/pacman.txt
   2. AUR               AUR helper + packages/aur.txt
   3. Backup            move conflicting configs aside, write a restore script
   4. Symlinks          link configs into ~/.config, create runtime dirs
   5. Zsh               ~/.zshenv, history, zinit pre-warm, chsh
   6. Paths             rewrite the two files that hardcode a username
   7. Theme             pick a wallpaper and run wallust
   8. Services          gcr-ssh-agent, swaync mask, scx_lavd, GPU monitor, NM check interval
   9. Extras            ocr-snipper (ALT+X), the nvim config, Lutris game-performance prefix
  10. Check             audit what is actually in place, then summarise
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)     CHECK_ONLY=1 ;;
        --dry-run)   DRY_RUN=1 ;;
        --yes|-y)    ASSUME_YES=1 ;;
        --help|-h)   usage; exit 0 ;;
        *)           usage >&2; die "Unknown option: $1" ;;
    esac
    shift
done

# Config directories linked from the repo into the user's XDG config directory.
LINK_DIRS=(hypr waybar kitty rofi wallust zsh)
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# ═══════════════════════════════════════════════════════════════════════════
# Preflight -- not skippable
# ═══════════════════════════════════════════════════════════════════════════

preflight() {
    [[ $EUID -ne 0 ]] || die "Do not run this as root. It installs into \$HOME, and sudo is used only where it is actually needed."
    command -v pacman >/dev/null || die "pacman not found. This installer is for Arch Linux and its derivatives."
    command -v git    >/dev/null || die "git not found. Install it first: sudo pacman -S git"
    [[ -f "$REPO/hypr/hyprland.lua" ]] || die "This does not look like the MyArch repo: $REPO"

    printf '%s\n' "$C_BOLD"
    cat <<'BANNER'
   __  __        _             _
  |  \/  |_   _ / \   _ __ ___| |__
  | |\/| | | | / _ \ | '__/ __| '_ \
  | |  | | |_| / ___ \| | | (__| | | |
  |_|  |_|\__, /_/   \_\_|  \___|_| |_|
          |___/
BANNER
    printf '%s' "$C_RESET"

    info "Repo:   $REPO"
    info "Home:   $HOME"
    info "Shell:  ${SHELL:-unknown}"
    (( DRY_RUN )) && warn "DRY RUN -- nothing will be modified."
    echo
    note "Ten stages, each asked about individually:"
    note "  1 packages   2 aur       3 backup    4 symlinks  5 zsh"
    note "  6 paths      7 theme     8 services  9 extras   10 check"
    echo

    ask "Ready to begin?" y || { info "Nothing done."; exit 0; }
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 1. Packages
# ═══════════════════════════════════════════════════════════════════════════

stage_packages() {
    step "1/10  Official packages"

    local manifest="$REPO/packages/pacman.txt"
    [[ -f "$manifest" ]] || { warn "packages/pacman.txt not found; skipping."; return; }

    local wanted=() missing=() p
    mapfile -t wanted < <(read_manifest "$manifest")
    info "${#wanted[@]} packages listed in packages/pacman.txt"

    for p in "${wanted[@]}"; do
        pacman -Qq -- "$p" &>/dev/null || missing+=("$p")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "All present already."
        return
    fi

    warn "${#missing[@]} missing:"
    printf '      %s\n' "${missing[@]}" | column -c 76 2>/dev/null || printf '      %s\n' "${missing[@]}"

    if ! ask "Install them with pacman?" y; then
        skip_stage "packages"
        return
    fi

    local pacman_args=(-S --needed)
    (( ASSUME_YES )) && pacman_args+=(--noconfirm)
    run sudo pacman "${pacman_args[@]}" "${missing[@]}" \
        && ok "Packages installed." \
        || warn "pacman exited non-zero -- some packages may be missing. Stage 10 will tell you which."
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 2. AUR
# ═══════════════════════════════════════════════════════════════════════════

detect_aur_helper() {
    local h
    for h in yay paru; do
        command -v "$h" >/dev/null && { echo "$h"; return 0; }
    done
    return 1
}

bootstrap_yay() {
    info "No AUR helper found. yay can be built from the AUR itself."
    note "Needs base-devel and a few minutes."
    ask "Bootstrap yay now?" y || return 1

    local tmp
    tmp="$(mktemp -d)"
    local pacman_args=(-S --needed base-devel git)
    (( ASSUME_YES )) && pacman_args+=(--noconfirm)
    run sudo pacman "${pacman_args[@]}" || return 1
    run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" || return 1
    if (( DRY_RUN )); then
        printf '    %s[dry-run]%s cd %s/yay-bin && makepkg -si\n' "$C_DIM" "$C_RESET" "$tmp"
    else
        ( cd "$tmp/yay-bin" && makepkg -si $( ((ASSUME_YES)) && echo --noconfirm ) ) || return 1
    fi
    rm -rf "$tmp"
    command -v yay >/dev/null
}

stage_aur() {
    step "2/10  AUR packages"

    local manifest="$REPO/packages/aur.txt"
    [[ -f "$manifest" ]] || { warn "packages/aur.txt not found; skipping."; return; }

    local wanted=() missing=() p helper
    mapfile -t wanted < <(read_manifest "$manifest")
    for p in "${wanted[@]}"; do
        pacman -Qq -- "$p" &>/dev/null || missing+=("$p")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "All present already."
        return
    fi

    warn "${#missing[@]} missing: ${missing[*]}"
    note "awww is the wallpaper daemon -- without it the wallpaper cycle and all"
    note "dynamic theming are dead. wallust generates every colour file."

    if ! helper="$(detect_aur_helper)"; then
        if bootstrap_yay; then
            helper=yay
        else
            warn "No AUR helper. Install these yourself: ${missing[*]}"
            skip_stage "aur"
            return
        fi
    fi
    info "Using $helper"

    if ! ask "Install with $helper?" y; then
        skip_stage "aur"
        return
    fi

    local args=(-S --needed)
    (( ASSUME_YES )) && args+=(--noconfirm)
    run "$helper" "${args[@]}" "${missing[@]}" \
        && ok "AUR packages installed." \
        || warn "$helper exited non-zero. Stage 10 will report what is still missing."
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. Backup
# ═══════════════════════════════════════════════════════════════════════════

# True when <path> is already the symlink we would create pointing at <target>.
is_correct_link() {
    local path="$1" target="$2"
    [[ -L "$path" ]] && [[ "$(readlink -f -- "$path")" == "$(readlink -f -- "$target")" ]]
}

# Move <path> into the backup dir, mirroring its position relative to $HOME so
# the tree stays readable and restoring is a plain mv back.
backup_item() {
    local path="$1" rel dest

    [[ -e "$path" || -L "$path" ]] || return 0

    rel="${path#"$HOME"/}"
    dest="$BACKUP_DIR/$rel"

    run mkdir -p "$(dirname "$dest")"
    run mv -- "$path" "$dest"
    run_sh "printf '%s\n' ${rel@Q} >> ${BACKUP_DIR@Q}/manifest.txt"
    BACKUP_MADE=1
    ok "Backed up ~/$rel"
}

write_restore_script() {
    (( BACKUP_MADE )) || return 0
    if (( DRY_RUN )); then
        printf '    %s[dry-run]%s write %s/restore.sh\n' "$C_DIM" "$C_RESET" "$BACKUP_DIR"
        return 0
    fi

    cat > "$BACKUP_DIR/restore.sh" <<'RESTORE_EOF'
#!/usr/bin/env bash
# Undo a MyArch install: remove the symlinks it created and move the originals
# back. Generated by install.sh -- the list comes from manifest.txt, which
# records exactly what was moved aside on that run.
set -euo pipefail

BACKUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$BACKUP/manifest.txt" ]] || { echo "No manifest.txt beside this script." >&2; exit 1; }

echo "Restoring from $BACKUP into $HOME"
while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="$BACKUP/$rel"
    dst="$HOME/$rel"
    [[ -e "$src" || -L "$src" ]] || { echo "  ?  missing in backup: $rel"; continue; }

    # Only ever remove a symlink. A real file or directory at the destination
    # was created after the backup and is not ours to delete.
    if [[ -L "$dst" ]]; then
        rm -- "$dst"
    elif [[ -e "$dst" ]]; then
        echo "  !  $dst exists and is not a symlink -- leaving it, backup kept at $src"
        continue
    fi

    mkdir -p "$(dirname "$dst")"
    mv -- "$src" "$dst"
    echo "  ok $rel"
done < "$BACKUP/manifest.txt"

echo
echo "Done. This backup directory can now be deleted."
RESTORE_EOF
    chmod +x "$BACKUP_DIR/restore.sh"
    ok "Restore script: $BACKUP_DIR/restore.sh"
}

stage_backup() {
    step "3/10  Backup existing configs"

    local conflicts=() d path
    for d in "${LINK_DIRS[@]}"; do
        path="$CONFIG_HOME/$d"
        is_correct_link "$path" "$REPO/$d" && continue
        [[ -e "$path" || -L "$path" ]] && conflicts+=("$path")
    done
    # Home-level zsh entry points.
    is_correct_link "$HOME/.zshenv" "$REPO/zsh/.zshenv" || \
        { [[ -e "$HOME/.zshenv" || -L "$HOME/.zshenv" ]] && conflicts+=("$HOME/.zshenv"); }
    for path in "$HOME/.zshrc" "$HOME/.zsh"; do
        [[ -e "$path" || -L "$path" ]] && conflicts+=("$path")
    done

    if [[ ${#conflicts[@]} -eq 0 ]]; then
        ok "Nothing in the way -- either already linked, or not present."
        return
    fi

    warn "${#conflicts[@]} path(s) would be replaced:"
    for path in "${conflicts[@]}"; do
        if [[ -L "$path" ]]; then
            note "$path  ->  $(readlink -- "$path")"
        else
            note "$path  ($([[ -d "$path" ]] && echo directory || echo file))"
        fi
    done
    info "They would move to $BACKUP_DIR, with a restore.sh to put them back."

    if ! ask "Back these up?" y; then
        warn "Without a backup, stage 4 would overwrite them. Skipping backup AND symlinks."
        skip_stage "backup"
        return 1
    fi

    local per_item=1
    ask "Back up all of them without asking each time?" y && per_item=0

    for path in "${conflicts[@]}"; do
        if (( per_item )) && ! ask "  back up $path?" y; then
            warn "Left in place: $path (stage 4 will not overwrite it)"
            continue
        fi
        backup_item "$path"
    done

    write_restore_script
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. Symlinks and runtime directories
# ═══════════════════════════════════════════════════════════════════════════

stage_symlinks() {
    step "4/10  Symlinks and directories"

    if ! ask "Link configs into ~/.config and create the runtime directories?" y; then
        skip_stage "symlinks"
        return
    fi

    run mkdir -p "$CONFIG_HOME"

    local d path
    for d in "${LINK_DIRS[@]}"; do
        path="$CONFIG_HOME/$d"
        if is_correct_link "$path" "$REPO/$d"; then
            ok "~/.config/$d already linked"
            continue
        fi
        if [[ -e "$path" && ! -L "$path" ]]; then
            err "~/.config/$d exists and was not backed up -- refusing to overwrite it."
            continue
        fi
        run ln -sfn "$REPO/$d" "$path"
        ok "~/.config/$d -> $REPO/$d"
    done

    # swayosd is NOT a symlink. There is no swayosd/ directory in this repo --
    # the folder exists only to hold the style.css wallust writes into it. The
    # old README told you to symlink it, which silently broke the theming.
    if [[ -L "$CONFIG_HOME/swayosd" ]]; then
        warn "$CONFIG_HOME/swayosd is a symlink (the old README's mistake)."
        if ask "Replace it with a real directory?" y; then
            backup_item "$CONFIG_HOME/swayosd"
            run mkdir -p "$CONFIG_HOME/swayosd"
            write_restore_script
            ok "$CONFIG_HOME/swayosd is now a real directory"
        fi
    else
        run mkdir -p "$CONFIG_HOME/swayosd"
        ok "$CONFIG_HOME/swayosd (real directory, holds wallust's style.css)"
    fi

    # Directories the scripts write into. awww-cycle.sh spins on an empty shuf
    # without the wallpaper dir; the screenshot binds and screen-record.sh
    # would fail on the other two.
    local dir
    for dir in "$HOME/Pictures/Wallpaper" "$HOME/Pictures/Screenshots" "$HOME/Videos/Recordings"; do
        if [[ -d "$dir" ]]; then
            ok "${dir/#"$HOME"/\~} exists"
        else
            run mkdir -p "$dir"
            ok "created ${dir/#"$HOME"/\~}"
        fi
    done
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 5. Zsh
#
# The load chain is order-sensitive and not obvious:
#
#   ~/.zshenv -> repo zsh/.zshenv   sets ZDOTDIR=$HOME/.config/zsh
#        └─ sources $ZDOTDIR/conf.d/*.zsh in glob order: binds, core, env, prompt
#             └─ core.zsh drives everything and sources .zshrc LAST
#
# So ~/.config/zsh must be linked (stage 4) BEFORE ~/.zshenv means anything.
# ═══════════════════════════════════════════════════════════════════════════

stage_zsh() {
    step "5/10  Zsh"

    if ! ask "Set up the zsh configuration?" y; then
        skip_stage "zsh"
        return
    fi

    # 1. The whole chain hangs off this link existing first.
    if [[ ! -d "$CONFIG_HOME/zsh" ]]; then
        err "~/.config/zsh is missing. Run stage 4 first -- without it \$ZDOTDIR points at nothing"
        err "and zsh loads none of this configuration."
        return
    fi
    ok "~/.config/zsh present (\$ZDOTDIR target)"

    # 2. ~/.zshenv is the one file zsh reads unprompted. Point it straight at
    #    the repo rather than hopping through ~/.config/zsh -- one less link to
    #    break.
    if is_correct_link "$HOME/.zshenv" "$REPO/zsh/.zshenv"; then
        ok "~/.zshenv already linked"
    elif [[ -e "$HOME/.zshenv" && ! -L "$HOME/.zshenv" ]]; then
        err "~/.zshenv exists as a real file and was not backed up -- refusing to overwrite."
    else
        run ln -sfn "$REPO/zsh/.zshenv" "$HOME/.zshenv"
        ok "~/.zshenv -> $REPO/zsh/.zshenv"
    fi

    # 3. ~/.zshrc is redundant here: ZDOTDIR means zsh reads
    #    ~/.config/zsh/.zshrc, and core.zsh sources it explicitly anyway.
    if [[ -L "$HOME/.zshrc" ]]; then
        note "~/.zshrc is a symlink, and redundant -- \$ZDOTDIR already points zsh"
        note "at ~/.config/zsh/.zshrc, which core.zsh sources itself."
        if ask "Remove the redundant ~/.zshrc symlink?" y; then
            run rm -- "$HOME/.zshrc"
            ok "removed ~/.zshrc"
        fi
    elif [[ -e "$HOME/.zshrc" ]]; then
        warn "~/.zshrc is a real file. Leaving it alone -- but note zsh will read it"
        warn "instead of the repo's, because it is found before \$ZDOTDIR is consulted."
    fi

    # 4. core.zsh's deferred-load hook toggles the read bit on .zshrc
    #    (chmod -r / chmod +r). Git does not track it, so a clone -- or a shell
    #    killed mid-defer -- can leave it unreadable and silently unsourced.
    if [[ -r "$REPO/zsh/.zshrc" ]]; then
        ok "zsh/.zshrc is readable"
    else
        run chmod +r "$REPO/zsh/.zshrc"
        ok "restored read permission on zsh/.zshrc (the deferred-load chmod trick)"
    fi

    # 5. HISTFILE lives in ZDOTDIR. core.zsh nags on every single shell if
    #    ~/.zsh_history exists while $HISTFILE does not.
    local histfile="$REPO/zsh/.zsh_history"
    if [[ -f "$histfile" ]]; then
        ok "history file present ($(wc -l < "$histfile" 2>/dev/null || echo 0) lines)"
    elif [[ -f "$HOME/.zsh_history" ]]; then
        warn "~/.zsh_history exists but \$HISTFILE ($histfile) does not."
        note "core.zsh prints a reminder about this on every shell until it is moved."
        if ask "Move ~/.zsh_history into place?" y; then
            run mv -- "$HOME/.zsh_history" "$histfile"
            ok "moved history to \$HISTFILE"
        fi
    else
        run touch "$histfile"
        ok "created empty history file"
    fi

    # 6. A .zcompdump carried in from another machine describes commands that
    #    may not exist here.
    if compgen -G "$REPO/zsh/.zcompdump*" >/dev/null; then
        if [[ "$REPO/zsh/.zcompdump" -ot "$REPO/zsh/conf.d/core.zsh" ]]; then
            warn "zsh/.zcompdump is older than conf.d/core.zsh -- likely stale."
            if ask "Delete it? (compinit regenerates it on next shell)" y; then
                run_sh "rm -f ${REPO@Q}/zsh/.zcompdump*"
                ok "removed stale completion cache"
            fi
        else
            ok "completion cache looks current"
        fi
    fi

    # 7. plugin.zsh clones zinit on first interactive shell and then fetches 11
    #    plugins over the network. Doing it here means the first real shell is
    #    not a minute-long stall, and failures surface now rather than later.
    local zinit_home="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
    if [[ -d "$zinit_home/.git" ]]; then
        ok "zinit already installed"
    else
        info "zinit is not installed. zsh/plugin.zsh would clone it on first shell."
        if ask "Install zinit now?" y; then
            run mkdir -p "$(dirname "$zinit_home")"
            run git clone https://github.com/zdharma-continuum/zinit.git "$zinit_home" \
                && ok "zinit installed" \
                || warn "zinit clone failed -- the first interactive shell will retry."
        fi
    fi

    if command -v zsh >/dev/null && [[ -d "$zinit_home/.git" || $DRY_RUN -eq 1 ]]; then
        note "11 plugins are fetched on first launch (autosuggestions, fzf-tab,"
        note "fast-syntax-highlighting, ...). That takes a minute and needs network."
        if ask "Pre-fetch them now, so your first shell starts instantly?" y; then
            if (( DRY_RUN )); then
                printf '    %s[dry-run]%s zsh -i -c exit\n' "$C_DIM" "$C_RESET"
            else
                info "Fetching plugins, please wait..."
                if timeout 300 zsh -i -c exit >/dev/null 2>&1; then
                    ok "plugins fetched"
                else
                    warn "Pre-fetch did not finish cleanly. Not fatal -- the first"
                    warn "interactive shell will finish the job."
                fi
            fi
        fi
    fi

    # 8. chsh needs the account password, so it cannot be silent.
    local zsh_bin
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        warn "zsh is not installed -- none of the above takes effect until it is."
    elif [[ "${SHELL:-}" == "$zsh_bin" ]]; then
        ok "zsh is already your login shell"
    else
        info "Login shell is ${SHELL:-unknown}, not $zsh_bin."
        if ask "Change it with chsh? (asks for your password; applies at next login)" y; then
            run chsh -s "$zsh_bin" \
                && ok "login shell changed -- log out and back in" \
                || warn "chsh failed. Run it yourself: chsh -s $zsh_bin"
        fi
    fi

    # Report, do not fix: which prompt engine will actually run.
    if command -v starship >/dev/null; then
        ok "prompt: starship"
        [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/starship/starship.toml" ]] \
            || note "No starship.toml -- stock defaults. This repo does not ship one."
    elif [[ -r /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
        ok "prompt: powerlevel10k"
        [[ -f "$HOME/.p10k.zsh" || -f "$REPO/zsh/.p10k.zsh" ]] \
            || note "No .p10k.zsh -- p10k will run its configuration wizard on first shell."
    else
        warn "prompt: neither starship nor powerlevel10k found; you get the zsh default."
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 6. Per-user path rewrite
#
# Two files point at the wallpaper by absolute path, and neither format expands
# $HOME: rofi's .rasi has no variable expansion, and hyprlock's path key is
# taken literally. On any account other than the one this repo was written on,
# both silently show nothing.
# ═══════════════════════════════════════════════════════════════════════════

WALLPAPER_LINK="$HOME/Pictures/Wallpaper/current_wallpaper"
HARDCODED_FILES=("rofi/themes/launcher.rasi" "hypr/hyprlock.conf")

paths_need_rewrite() {
    local f
    for f in "${HARDCODED_FILES[@]}"; do
        grep -q "$WALLPAPER_LINK" "$REPO/$f" || return 0
    done
    return 1
}

stage_paths() {
    step "6/10  Per-user paths"

    if ! paths_need_rewrite; then
        ok "Both files already point at $WALLPAPER_LINK"
        return
    fi

    warn "These hardcode a different user's home directory:"
    local f
    for f in "${HARDCODED_FILES[@]}"; do
        note "$f: $(grep -oE '/[^"[:space:]]*current_wallpaper' "$REPO/$f" | head -1)"
    done
    info "They would be rewritten to $WALLPAPER_LINK"

    if ! ask "Rewrite them?" y; then
        warn "Left as-is. Your wallpaper will not show on the lock screen or in the"
        warn "rofi launcher until these two point at your own home directory."
        skip_stage "paths"
        return
    fi

    for f in "${HARDCODED_FILES[@]}"; do
        run sed -i -E "s|/[^\"[:space:]]*/Pictures/Wallpaper|$HOME/Pictures/Wallpaper|g" "$REPO/$f"
        ok "rewrote $f"
    done

    # These are tracked files, so the rewrite shows up as a permanent local diff.
    warn "This edits tracked files -- git status is now dirty, and a future pull"
    warn "of these two files will conflict."
    if ask "Tell git to ignore your local changes to them? (--skip-worktree)" y; then
        for f in "${HARDCODED_FILES[@]}"; do
            if run_sh "cd ${REPO@Q} && git update-index --skip-worktree ${f@Q}"; then
                SKIPWORKTREE_FILES+=("$f")
                ok "git will ignore local changes to $f"
            fi
        done
        note "To undo later:"
        note "  cd $REPO && git update-index --no-skip-worktree ${HARDCODED_FILES[*]}"
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 7. Theme generation
#
# wallust writes generated files that are gitignored, so a fresh clone has none of
# them. hyprlock.conf does `source = ...hyprlock-colors.conf`, and a missing
# source file is a hard error -- hyprlock will not start.
# ═══════════════════════════════════════════════════════════════════════════

WALLUST_TARGETS=(
    "$CONFIG_HOME/hypr/hyprlock-colors.conf"
    "$CONFIG_HOME/hypr/config/wallust.lua"
    "$CONFIG_HOME/kitty/kitty-theme.conf"
    "$CONFIG_HOME/swayosd/style.css"
    "$CONFIG_HOME/waybar/style/wallust.css"
    "$CONFIG_HOME/zsh/wallust-colors.zsh"
    "$CONFIG_HOME/rofi/themes/colours.rasi"
)

find_wallpapers() {
    find "$HOME/Pictures/Wallpaper" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | sort
}

stage_theme() {
    step "7/10  Theme generation"

    if ! command -v wallust >/dev/null; then
        warn "wallust is not installed -- cannot generate colours."
        warn "hyprlock will fail to start without ~/.config/hypr/hyprlock-colors.conf."
        skip_stage "theme"
        return
    fi

    local images=()
    mapfile -t images < <(find_wallpapers)

    if [[ ${#images[@]} -eq 0 ]]; then
        warn "No images in ~/Pictures/Wallpaper."
        note "Without at least one, awww-cycle.sh spins on an empty shuf and"
        note "hyprlock has no colour file to source -- which is a hard error."
        if ask "Copy images in from another directory now?" y; then
            local src
            printf '  %s?%s Source directory: ' "$C_YELLOW" "$C_RESET"
            read -r src || src=""
            src="${src/#\~/$HOME}"
            if [[ -d "$src" ]]; then
                run_sh "find ${src@Q} -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\) -exec cp -n {} ${HOME@Q}/Pictures/Wallpaper/ \;"
                mapfile -t images < <(find_wallpapers)
                ok "${#images[@]} image(s) now in ~/Pictures/Wallpaper"
            else
                err "Not a directory: $src"
            fi
        fi
    fi

    if [[ ${#images[@]} -eq 0 ]]; then
        err "Still no wallpapers. Add one to ~/Pictures/Wallpaper and re-run:"
        err "  wallust run ~/Pictures/Wallpaper/<image>"
        skip_stage "theme"
        return
    fi

    # Prefer whatever current_wallpaper already points at, so re-running does
    # not silently change the user's theme.
    local chosen=""
    if [[ -e "$WALLPAPER_LINK" ]]; then
        chosen="$(readlink -f -- "$WALLPAPER_LINK")"
        info "Using the current wallpaper: $(basename "$chosen")"
    elif [[ ${#images[@]} -gt 0 ]]; then
        chosen="${images[0]}"
        info "Using $(basename "$chosen") (${#images[@]} available; the cycle script"
        info "picks a new one every 200s once Hyprland is running)"
    fi

    if ! ask "Run wallust to generate the colour files?" y; then
        warn "Skipping. hyprlock will not start until these exist."
        skip_stage "theme"
        return
    fi

    if [[ ! -f "$chosen" ]]; then
        err "Selected wallpaper is not a regular file: $chosen"
        skip_stage "theme"
        return
    fi

    run ln -sfn "$chosen" "$WALLPAPER_LINK"
    if run wallust run "$chosen"; then
        ok "wallust ran"
    else
        err "wallust failed."
        return
    fi

    local t missing=0
    for t in "${WALLUST_TARGETS[@]}"; do
        if (( DRY_RUN )); then continue; fi
        if [[ -s "$t" ]]; then
            ok "${t/#"$HOME"/\~}"
        else
            err "${t/#"$HOME"/\~} was not written"
            missing=1
        fi
    done
    if (( missing )); then
        warn "Check ~/.config/wallust/wallust.toml -- a target directory may be missing."
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 8. Systemd user units
# ═══════════════════════════════════════════════════════════════════════════

stage_services() {
    step "8/10  Systemd user units"

    if ! command -v systemctl >/dev/null; then
        warn "systemctl not found; skipping."
        return
    fi

    if ! ask "Configure the two user units this setup depends on?" y; then
        skip_stage "services"
        return
    fi

    # hypr/config/variables.lua points SSH_AUTH_SOCK at $XDG_RUNTIME_DIR/gcr/ssh.
    # gnome-keyring no longer serves an ssh-agent, so without this socket
    # `ssh-add -l` just says "Error connecting to agent".
    if systemctl --user is-active --quiet gcr-ssh-agent.socket 2>/dev/null; then
        ok "gcr-ssh-agent.socket already active"
    else
        info "SSH_AUTH_SOCK points at \$XDG_RUNTIME_DIR/gcr/ssh, served by this socket."
        run systemctl --user enable --now gcr-ssh-agent.socket \
            && ok "gcr-ssh-agent.socket enabled" \
            || warn "Could not enable it -- is the gcr package installed?"
    fi

    # swaync is started from autostart.lua. Left unmasked, D-Bus activates a
    # second copy at login which fails against the bus name the first already
    # holds, leaving a permanently failed unit.
    if [[ "$(systemctl --user is-enabled swaync.service 2>/dev/null)" == "masked" ]]; then
        ok "swaync.service already masked"
    else
        info "swaync is started by autostart.lua; the unit must be masked or D-Bus"
        info "activates a duplicate that fails and stays failed."
        run systemctl --user mask swaync.service \
            && ok "swaync.service masked" \
            || warn "Could not mask swaync.service."
    fi

    setup_scx_loader
    setup_gpu_monitor
    setup_nm_connectivity
    return 0
}

# waybar's "no internet" badge reads NetworkManager's connectivity state. NM
# re-checks only every 300 s by default, so a drop mid-session could take five
# minutes to show; this drops it to 60 s.
NM_CONN_SRC="$REPO/packages/NetworkManager/30-connectivity-interval.conf"
NM_CONN_DST="/etc/NetworkManager/conf.d/30-connectivity-interval.conf"

setup_nm_connectivity() {
    command -v NetworkManager >/dev/null || return 0

    if cmp -s "$NM_CONN_SRC" "$NM_CONN_DST"; then
        ok "NetworkManager connectivity check every 60 s"
        return 0
    fi

    info "waybar shows \"no internet\" from NetworkManager's connectivity check,"
    info "which by default re-runs only every 5 minutes."
    ask "Re-check every 60 s instead?" y || { skip_stage "nm-connectivity"; return 0; }

    run sudo install -Dm644 "$NM_CONN_SRC" "$NM_CONN_DST" \
        && run sudo systemctl reload NetworkManager \
        && ok "connectivity check every 60 s" \
        || warn "Could not install $NM_CONN_DST."
    return 0
}

# waybar's GPU module runs intel_gpu_top, which needs CAP_PERFMON to read the
# GPU counters. A file capability is lost whenever intel-gpu-tools upgrades
# (pacman replaces the binary), so a pacman hook re-applies it every time.
GPU_HOOK_SRC="$REPO/packages/hooks/intel-gpu-top-perfmon.hook"
GPU_HOOK_DST="/etc/pacman.d/hooks/intel-gpu-top-perfmon.hook"

gpu_top_capable() { getcap /usr/bin/intel_gpu_top 2>/dev/null | grep -q cap_perfmon; }

setup_gpu_monitor() {
    command -v intel_gpu_top >/dev/null || return 0

    if gpu_top_capable && cmp -s "$GPU_HOOK_SRC" "$GPU_HOOK_DST"; then
        ok "intel_gpu_top has CAP_PERFMON, pacman hook in place"
        return 0
    fi

    info "waybar's GPU module needs intel_gpu_top to have CAP_PERFMON; without it"
    info "the module stays blank. A pacman hook keeps it across package updates."
    ask "Grant it and install the hook?" y || { skip_stage "gpu-monitor"; return 0; }

    run sudo install -Dm644 "$GPU_HOOK_SRC" "$GPU_HOOK_DST" \
        && ok "installed $GPU_HOOK_DST" \
        || warn "Could not install the pacman hook."
    run sudo setcap cap_perfmon+ep /usr/bin/intel_gpu_top \
        && ok "intel_gpu_top: cap_perfmon+ep" \
        || warn "setcap failed."
    return 0
}

# sched-ext scheduler for Game Mode. CachyOS's power-profiles-daemon switches
# the running scx scheduler to its Gaming mode on the performance profile and
# back to Auto on balanced -- but only if scx_loader is running one. Starting
# one on demand needs polkit auth_admin every time, so run scx_lavd from boot
# in Auto mode, as the CachyOS wiki recommends for gaming.
SCX_CONFIG="/etc/scx_loader/config.toml"

scx_running() { scxctl get 2>/dev/null | grep -qv 'no scx scheduler'; }

setup_scx_loader() {
    command -v scx_loader >/dev/null || return 0

    if scx_running; then
        ok "sched-ext scheduler running: $(scxctl get 2>/dev/null)"
        return 0
    fi

    info "No sched-ext scheduler is running. Game Mode switches scx_lavd to its"
    info "Gaming mode through the performance profile, which needs it running."
    ask "Run scx_lavd from boot (Auto mode) via scx_loader?" y || { skip_stage "scx"; return 0; }

    if [[ -f "$SCX_CONFIG" ]] && grep -qE '^[[:space:]]*default_sched[[:space:]]*=' "$SCX_CONFIG"; then
        ok "$SCX_CONFIG already names a scheduler -- leaving it as is"
    else
        local backup_note
        [[ -f "$SCX_CONFIG" ]] && backup_note="(existing file kept as $SCX_CONFIG.bak)" || backup_note=""
        run_sh "sudo mkdir -p /etc/scx_loader && { [ ! -f ${SCX_CONFIG@Q} ] || sudo cp ${SCX_CONFIG@Q} ${SCX_CONFIG@Q}.bak; } && printf '%s\n' 'default_sched = \"scx_lavd\"' 'default_mode = \"Auto\"' | sudo tee ${SCX_CONFIG@Q} >/dev/null" \
            && ok "wrote $SCX_CONFIG $backup_note" \
            || { warn "Could not write $SCX_CONFIG."; return 0; }
    fi

    run sudo systemctl enable --now scx_loader.service \
        && ok "scx_loader enabled" \
        || warn "Could not enable scx_loader.service."
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 9. External repos
#
# Both live in their own repositories rather than being vendored here, so they
# stay independently updatable.
# ═══════════════════════════════════════════════════════════════════════════

OCR_REPO="https://github.com/Darunesh1/ocr-snipper.git"
OCR_BRANCH="master"          # `main` holds only a README; the code is on master
OCR_SRC="$HOME/.local/src/ocr-snipper"
OCR_BIN="$HOME/.local/bin/ocr-snipper"

NVIM_REPO="https://github.com/Darunesh1/my_nvim.git"
NVIM_DIR="$HOME/.config/nvim"

# leptess binds Tesseract through bindgen, so libclang is a build-time
# requirement on top of the OCR libraries themselves. main.rs initialises
# Tesseract with "eng+tam": without the Tamil data every run fails with
# "Tesseract initialization failed". notify-send reports the result.
OCR_DEPS=(clang tesseract tesseract-data-eng tesseract-data-tam leptonica libnotify)
OCR_TESSDATA=(/usr/share/tessdata/eng.traineddata /usr/share/tessdata/tam.traineddata)

# True when cargo actually runs. `command -v cargo` is not enough: the rustup
# package ships a /usr/bin/cargo shim that fails until a toolchain is set.
rust_ready() { cargo --version >/dev/null 2>&1; }

install_ocr_snipper() {
    info "ALT+X is bound to $OCR_BIN, which is not part of this repo."
    note "It is a small Rust program: slurp a region, grim it, OCR it with"
    note "Tesseract, put the text on the clipboard."

    local missing=() d
    for d in "${OCR_DEPS[@]}"; do
        pacman -Qq -- "$d" &>/dev/null || missing+=("$d")
    done
    command -v rustup >/dev/null || rust_ready || missing+=(rustup)

    # Dependencies first, even when the binary exists: a built binary without
    # the Tamil tessdata is just as dead as no binary.
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Dependencies missing: ${missing[*]}"
        if ask "Install them?" y; then
            local args=(-S --needed)
            (( ASSUME_YES )) && args+=(--noconfirm)
            run sudo pacman "${args[@]}" "${missing[@]}" || { err "Dependency install failed."; return 1; }
        else
            skip_stage "ocr-snipper"
            return 0
        fi
    fi

    if [[ -x "$OCR_BIN" ]]; then
        ok "already installed at ${OCR_BIN/#"$HOME"/\~}"
        ask "Rebuild it from the latest source?" n || return 0
    else
        ask "Build and install it?" y || { skip_stage "ocr-snipper"; return 0; }
    fi

    if ! rust_ready; then
        info "rustup is installed but has no default toolchain, so cargo cannot run."
        if ask "Install the stable toolchain now? (rustup default stable, ~1 GB)" y; then
            run rustup default stable || warn "rustup failed."
        fi
    fi
    if ! rust_ready && (( ! DRY_RUN )); then
        err "No working Rust toolchain. Run 'rustup default stable', then re-run this stage."
        return 1
    fi

    if [[ -d "$OCR_SRC/.git" ]]; then
        run_sh "cd ${OCR_SRC@Q} && git fetch --quiet origin ${OCR_BRANCH@Q} && git checkout --quiet ${OCR_BRANCH@Q} && git pull --quiet" \
            || warn "Could not update the existing checkout; building what is there."
    else
        run mkdir -p "$(dirname "$OCR_SRC")"
        run git clone --branch "$OCR_BRANCH" "$OCR_REPO" "$OCR_SRC" \
            || { err "Clone failed."; return 1; }
    fi

    info "Building (first build pulls crates and compiles bindgen -- a few minutes)..."
    if run_sh "cd ${OCR_SRC@Q} && cargo build --release"; then
        run install -Dm755 "$OCR_SRC/target/release/ocr-snipper" "$OCR_BIN"
        ok "installed ${OCR_BIN/#"$HOME"/\~} -- ALT+X is live"
        note "~/.local/bin is already on PATH via zsh/conf.d/env.zsh."
    else
        err "Build failed. ALT+X stays inert; nothing else is affected."
        return 1
    fi
}

install_nvim_config() {
    info "The neovim config lives in its own repo: $NVIM_REPO"

    if [[ -d "$NVIM_DIR/.git" ]]; then
        local origin
        origin="$(git -C "$NVIM_DIR" remote get-url origin 2>/dev/null || echo unknown)"
        ok "~/.config/nvim is already a git checkout of $origin"
        return 0
    fi

    ask "Clone it into ~/.config/nvim?" y || { skip_stage "nvim"; return 0; }

    if [[ -e "$NVIM_DIR" ]]; then
        warn "~/.config/nvim already exists."
        ask "Back it up and replace it?" y || return 0
        backup_item "$NVIM_DIR"
        write_restore_script
    fi

    run git clone "$NVIM_REPO" "$NVIM_DIR" \
        && ok "~/.config/nvim cloned (plugins install on first nvim launch)" \
        || err "Clone failed."
}

# Lutris 0.5.22 keeps its config in its data dir when ~/.config/lutris does
# not exist -- which is the case here.
lutris_system_yml() {
    if [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/lutris" ]]; then
        echo "${XDG_CONFIG_HOME:-$HOME/.config}/lutris/system.yml"
    else
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/lutris/system.yml"
    fi
}

# CachyOS wiki: put game-performance in Lutris's Command prefix. While a game
# runs it holds the performance profile (so scx Gaming mode too) and inhibits
# idle; the previous profile comes back when the game exits.
setup_lutris_prefix() {
    command -v lutris >/dev/null || return 0
    command -v game-performance >/dev/null || return 0

    local yml
    yml="$(lutris_system_yml)"
    if grep -qE '^[[:space:]]+prefix_command:' "$yml" 2>/dev/null; then
        ok "Lutris command prefix already set: $(sed -nE 's/^[[:space:]]+prefix_command:[[:space:]]*//p' "$yml")"
        return 0
    fi

    info "Lutris: every game can launch through CachyOS's game-performance wrapper."
    ask "Set Lutris's global command prefix to game-performance?" y || { skip_stage "lutris"; return 0; }

    if [[ ! -f "$yml" ]]; then
        run mkdir -p "$(dirname "$yml")"
        run_sh "printf 'system:\n  prefix_command: game-performance\n' > ${yml@Q}"
    elif grep -qE '^system:' "$yml"; then
        run sed -i '/^system:/a\  prefix_command: game-performance' "$yml"
    else
        run_sh "printf 'system:\n  prefix_command: game-performance\n' >> ${yml@Q}"
    fi
    ok "Lutris command prefix: game-performance (${yml/#"$HOME"/\~})"
}

stage_extras() {
    step "9/10  Extras"

    if ask "Install the ALT+X OCR snipper?" y; then
        install_ocr_snipper || true
    else
        skip_stage "ocr-snipper"
    fi

    echo
    install_nvim_config || true

    echo
    setup_lutris_prefix || true
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# 10. Final check and summary
#
# Deliberately independent of what the install run did: it re-inspects the
# system from scratch, so it is equally useful months later as
# `./install.sh --check` when something has stopped working.
# ═══════════════════════════════════════════════════════════════════════════

N_OK=0; N_MISSING=0; N_WARN=0; N_SKIP=0

group() { printf '\n  %s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

# row <OK|MISSING|SKIPPED|WARN> <label> [detail]
row() {
    local status="$1" label="$2" detail="${3:-}" color tag
    case "$status" in
        OK)      color="$C_GREEN";  tag="  OK   "; N_OK=$((N_OK + 1)) ;;
        MISSING) color="$C_RED";    tag="MISSING"; N_MISSING=$((N_MISSING + 1)) ;;
        SKIPPED) color="$C_DIM";    tag="SKIPPED"; N_SKIP=$((N_SKIP + 1)) ;;
        WARN|*)  color="$C_YELLOW"; tag=" WARN  "; N_WARN=$((N_WARN + 1)) ;;
    esac
    printf '    %s[%s]%s %-34s %s%s%s\n' \
        "$color" "$tag" "$C_RESET" "$label" "$C_DIM" "$detail" "$C_RESET"
}

check_manifest() {
    local file="$1" label="$2"
    [[ -f "$file" ]] || { row WARN "$label" "manifest not found"; return; }

    local wanted=() missing=() p
    mapfile -t wanted < <(read_manifest "$file")
    for p in "${wanted[@]}"; do
        pacman -Qq -- "$p" &>/dev/null || missing+=("$p")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        row OK "$label" "${#wanted[@]}/${#wanted[@]} installed"
    else
        row MISSING "$label" "${#missing[@]} missing: ${missing[*]}"
    fi
}

stage_check() {
    step "10/10  Final check"
    info "Auditing what is actually in place -- not what this run did."

    # ── Packages ────────────────────────────────────────────────────────────
    group "Packages"
    check_manifest "$REPO/packages/pacman.txt" "official repo packages"
    check_manifest "$REPO/packages/aur.txt"    "AUR packages"

    # ── Binaries ────────────────────────────────────────────────────────────
    # Commands the configs call directly. Package presence does not guarantee
    # these, and each failure is a specific dead feature.
    group "Runtime binaries"
    local b why
    while IFS='|' read -r b why; do
        [[ -n "$b" ]] || continue
        if command -v "$b" >/dev/null; then
            row OK "$b" "$why"
        else
            row MISSING "$b" "$why"
        fi
    done <<'BINARIES'
awww|wallpaper daemon (autostart, cycle script)
wallust|generates every colour file
swayosd-server|volume/brightness OSD
swaync|notifications
rofimoji|emoji picker (SUPER+.)
cliphist|clipboard history (SUPER+V)
wf-recorder|screen recording (SUPER+SHIFT+P)
grim|screenshots
slurp|region select
powerprofilesctl|power profile menu (SUPER+SHIFT+G)
checkupdates|waybar custom/updates
intel_gpu_top|waybar custom/gpu
fd|file finder (SUPER+SHIFT+E)
jq|window switcher (SUPER+Tab)
udiskie|removable media automount
nm-applet|network tray icon (autostart)
blueman-applet|bluetooth tray icon (autostart)
notify-send|notifications from scripts and ocr-snipper
BINARIES

    # ── Symlinks ────────────────────────────────────────────────────────────
    group "Config links"
    local d path
    for d in "${LINK_DIRS[@]}"; do
        path="$CONFIG_HOME/$d"
        if is_correct_link "$path" "$REPO/$d"; then
            row OK "~/.config/$d" "-> repo"
        elif [[ -L "$path" ]]; then
            row MISSING "~/.config/$d" "links elsewhere: $(readlink -- "$path")"
        elif [[ -e "$path" ]]; then
            row MISSING "~/.config/$d" "exists but is not a link into the repo"
        else
            row MISSING "~/.config/$d" "absent"
        fi
    done
    # This one must NOT be a symlink -- see stage 4.
    if [[ -L "$CONFIG_HOME/swayosd" ]]; then
        row MISSING "$CONFIG_HOME/swayosd" "is a symlink; must be a real directory"
    elif [[ -d "$CONFIG_HOME/swayosd" ]]; then
        row OK "$CONFIG_HOME/swayosd" "real directory (correct)"
    else
        row MISSING "$CONFIG_HOME/swayosd" "absent; wallust cannot write style.css"
    fi

    # ── Runtime directories ─────────────────────────────────────────────────
    group "Runtime directories"
    local n
    if [[ -d "$HOME/Pictures/Wallpaper" ]]; then
        n="$(find_wallpapers | wc -l)"
        if [[ "$n" -gt 0 ]]; then
            row OK "~/Pictures/Wallpaper" "$n image(s)"
        else
            row WARN "~/Pictures/Wallpaper" "empty; awww-cycle.sh spins on an empty shuf"
        fi
    else
        row MISSING "~/Pictures/Wallpaper" "absent"
    fi
    for path in "$HOME/Pictures/Screenshots" "$HOME/Videos/Recordings"; do
        [[ -d "$path" ]] && row OK "${path/#"$HOME"/\~}" "" || row MISSING "${path/#"$HOME"/\~}" "absent"
    done

    # ── Zsh ─────────────────────────────────────────────────────────────────
    group "Zsh"
    if is_correct_link "$HOME/.zshenv" "$REPO/zsh/.zshenv"; then
        row OK "~/.zshenv" "-> repo (sets ZDOTDIR)"
    elif [[ -e "$HOME/.zshenv" ]]; then
        row WARN "~/.zshenv" "exists but does not resolve into the repo"
    else
        row MISSING "~/.zshenv" "absent; zsh loads none of this config"
    fi
    [[ -r "$REPO/zsh/.zshrc" ]] \
        && row OK "zsh/.zshrc readable" "" \
        || row MISSING "zsh/.zshrc readable" "chmod +r it; the defer hook left it unreadable"
    [[ -f "$REPO/zsh/.zsh_history" ]] \
        && row OK "\$HISTFILE" "zsh/.zsh_history" \
        || row WARN "\$HISTFILE" "absent; core.zsh nags on every shell"
    [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git/.git" ]] \
        && row OK "zinit" "installed" \
        || row MISSING "zinit" "plugin.zsh will clone it on first shell"
    if [[ "${SHELL:-}" == "$(command -v zsh 2>/dev/null)" ]]; then
        row OK "login shell" "zsh"
    else
        row WARN "login shell" "${SHELL:-unknown}; run chsh -s \$(command -v zsh)"
    fi
    if command -v starship >/dev/null; then
        row OK "prompt" "starship"
    elif [[ -r /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
        row OK "prompt" "powerlevel10k"
    else
        row WARN "prompt" "neither starship nor p10k; zsh default"
    fi

    # ── Theme ───────────────────────────────────────────────────────────────
    group "Generated theme files"
    local t
    for t in "${WALLUST_TARGETS[@]}"; do
        if [[ -s "$t" ]]; then
            row OK "${t/#"$HOME"/\~}" ""
        elif [[ "$t" == *hyprlock-colors.conf ]]; then
            # hyprlock.conf does `source =` on this. Missing is a hard error.
            row MISSING "${t/#"$HOME"/\~}" "hyprlock will NOT START without this"
        else
            row MISSING "${t/#"$HOME"/\~}" "run: wallust run <wallpaper>"
        fi
    done
    [[ -e "$WALLPAPER_LINK" ]] \
        && row OK "current_wallpaper" "-> $(basename "$(readlink -f -- "$WALLPAPER_LINK")")" \
        || row MISSING "current_wallpaper" "the symlink both hardcoded files point at"

    # ── Paths ───────────────────────────────────────────────────────────────
    group "Per-user paths"
    local f
    for f in "${HARDCODED_FILES[@]}"; do
        if grep -q "$WALLPAPER_LINK" "$REPO/$f"; then
            row OK "$f" "points at your \$HOME"
        else
            row MISSING "$f" "points elsewhere: $(grep -oE '/[^"[:space:]]*current_wallpaper' "$REPO/$f" | head -1)"
        fi
    done

    # ── Services ────────────────────────────────────────────────────────────
    group "Systemd user units"
    if command -v systemctl >/dev/null; then
        systemctl --user is-active --quiet gcr-ssh-agent.socket 2>/dev/null \
            && row OK "gcr-ssh-agent.socket" "active" \
            || row MISSING "gcr-ssh-agent.socket" "ssh-add will fail; SSH_AUTH_SOCK points here"
        [[ "$(systemctl --user is-enabled swaync.service 2>/dev/null)" == "masked" ]] \
            && row OK "swaync.service" "masked (correct)" \
            || row WARN "swaync.service" "not masked; D-Bus will start a duplicate that fails"
    else
        row SKIPPED "systemd units" "systemctl not available"
    fi
    if command -v NetworkManager >/dev/null; then
        cmp -s "$NM_CONN_SRC" "$NM_CONN_DST" \
            && row OK "NM connectivity interval" "60 s (no-internet badge)" \
            || row WARN "NM connectivity interval" "default 300 s; no-internet badge can lag 5 min"
    fi
    if command -v intel_gpu_top >/dev/null; then
        if gpu_top_capable; then
            [[ -f "$GPU_HOOK_DST" ]] \
                && row OK "intel_gpu_top CAP_PERFMON" "set, pacman hook keeps it" \
                || row WARN "intel_gpu_top CAP_PERFMON" "set, but no pacman hook; the next update drops it"
        else
            row WARN "intel_gpu_top CAP_PERFMON" "missing; waybar GPU module will be blank"
        fi
    fi
    if command -v scxctl >/dev/null; then
        scx_running \
            && row OK "sched-ext scheduler" "$(scxctl get 2>/dev/null)" \
            || row WARN "sched-ext scheduler" "none running; Game Mode cannot switch to scx Gaming mode"
    fi

    # ── Extras ──────────────────────────────────────────────────────────────
    group "Extras"
    local tessdata_missing=()
    for t in "${OCR_TESSDATA[@]}"; do
        [[ -f "$t" ]] || tessdata_missing+=("$(basename "$t")")
    done
    if [[ ! -x "$OCR_BIN" ]]; then
        if rust_ready; then
            row WARN "ocr-snipper" "not built; ALT+X is inert (optional, stage 9)"
        else
            row WARN "ocr-snipper" "not built, and no Rust toolchain: rustup default stable"
        fi
    elif [[ ${#tessdata_missing[@]} -gt 0 ]]; then
        row WARN "ocr-snipper" "built, but missing ${tessdata_missing[*]}; ALT+X fails"
    else
        row OK "ocr-snipper" "ALT+X works"
    fi
    [[ -d "$NVIM_DIR" ]] \
        && row OK "~/.config/nvim" "present" \
        || row WARN "~/.config/nvim" "not installed (optional)"
    if command -v lutris >/dev/null; then
        grep -qE '^[[:space:]]+prefix_command:[[:space:]]*game-performance' "$(lutris_system_yml)" 2>/dev/null \
            && row OK "Lutris command prefix" "game-performance" \
            || row WARN "Lutris command prefix" "not game-performance (optional, stage 9)"
    fi

    # ── Hardware ────────────────────────────────────────────────────────────
    # Always a reminder: these cannot be verified, only compared.
    group "Hardware-specific (always check by hand)"
    local cfg_out real_out cfg_if real_if
    cfg_out="$(grep -oE 'output[[:space:]]*=[[:space:]]*"[^"]+"' "$REPO/hypr/config/monitors.lua" | head -1 | grep -oE '"[^"]+"' | tr -d '"')"
    real_out="$(hyprctl monitors 2>/dev/null | awk '/^Monitor/ {print $2; exit}' || true)"
    row WARN "monitors.lua output" "config: ${cfg_out:-?}${real_out:+   detected: $real_out}"
    cfg_if="$(grep -oE '"interface"[[:space:]]*:[[:space:]]*"[^"]+"' "$REPO/waybar/config.jsonc" | head -1 | grep -oE '"[^"]+"$' | tr -d '"')"
    real_if="$(ip -o link 2>/dev/null | awk -F': ' '$2 ~ /^wl/ {print $2; exit}' || true)"
    row WARN "waybar network interface" "config: ${cfg_if:-?}${real_if:+   detected: $real_if}"
    return 0
}

print_summary() {
    step "Summary"

    printf '    %s%d OK%s   %s%d missing%s   %s%d warnings%s   %s%d skipped%s\n\n' \
        "$C_GREEN" "$N_OK" "$C_RESET" \
        "$C_RED" "$N_MISSING" "$C_RESET" \
        "$C_YELLOW" "$N_WARN" "$C_RESET" \
        "$C_DIM" "$N_SKIP" "$C_RESET"

    if [[ ${#SKIPPED_STAGES[@]} -gt 0 ]]; then
        warn "Stages you skipped: ${SKIPPED_STAGES[*]}"
        note "Re-run ./install.sh at any time -- completed stages are no-ops."
    fi

    if (( BACKUP_MADE )); then
        info "Your previous configs were moved to:"
        note "$BACKUP_DIR"
        note "Undo everything with:  $BACKUP_DIR/restore.sh"
    fi

    if [[ ${#SKIPWORKTREE_FILES[@]} -gt 0 ]]; then
        info "git is ignoring your local changes to: ${SKIPWORKTREE_FILES[*]}"
        note "Undo with: git update-index --no-skip-worktree ${SKIPWORKTREE_FILES[*]}"
    fi

    echo
    printf '  %sNext:%s\n' "$C_BOLD" "$C_RESET"
    note "1. Set your monitor in hypr/config/monitors.lua"
    note "   (run 'hyprctl monitors' from inside Hyprland to get the name)"
    note "2. Check the network interface in waybar/config.jsonc"
    note "3. Start Hyprland: pick it at your display manager, or 'exec Hyprland' from a TTY"
    if [[ "${SHELL:-}" != "$(command -v zsh 2>/dev/null)" ]]; then
        note "4. Log out and back in for the zsh login shell to take effect"
    fi
    echo
    note "Audit this setup any time with:  ./install.sh --check"
    echo
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

main() {
    if (( CHECK_ONLY )); then
        stage_check
        print_summary
        # Non-zero when something is actually missing, so --check is usable in
        # a one-liner. Warnings alone are not a failure.
        if [[ $N_MISSING -eq 0 ]]; then exit 0; else exit 1; fi
    fi

    preflight
    stage_packages
    stage_aur
    if stage_backup; then
        stage_symlinks
    else
        warn "Skipping symlinks too -- nothing was backed up."
        SKIPPED_STAGES+=("symlinks")
    fi
    stage_zsh
    stage_paths
    stage_theme
    stage_services
    stage_extras
    stage_check
    print_summary

    # An install run always succeeds: skipping a stage is a choice, not a
    # failure. Use --check when you want the exit code to mean something.
    exit 0
}

main "$@"
