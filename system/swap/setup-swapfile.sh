#!/usr/bin/env bash

# Give this machine real swap on disk, to back the zram swap that is already there.
#
#   sudo ./setup-swapfile.sh              # 8 GiB at /swap/swapfile
#   sudo ./setup-swapfile.sh --size 16G
#   sudo ./setup-swapfile.sh --remove
#
# Why, when zram already exists: zram IS RAM. It compresses pages in place, so
# it buys maybe 2-3x on 8 GB of memory and then there is nowhere left to go.
# There was no disk swap at all on this system (`swapon --show` listed only
# /dev/zram0), so "out of memory" meant out of memory, full stop -- and
# systemd-oomd reacted by killing the cgroup holding the desktop. Twice.
#
# A swapfile on disk is slow, and that is fine: it is not meant to be fast, it
# is meant to exist. Cold pages go there instead of the machine hitting a wall.
# `pri=10` against zram's `pri=100` means the kernel always fills fast zram
# first and only reaches for the disk when zram is genuinely exhausted.
#
# btrfs is picky about swapfiles -- they must not be copy-on-write, must not be
# compressed, and must not sit anywhere that gets snapshotted (a snapshot of a
# swapfile is a corrupt swapfile, and snapper snapshots @ on every pacman run).
# Two things handle that:
#
#   * a dedicated @swap subvolume, outside @ and so outside snapper's reach
#   * `btrfs filesystem mkswapfile`, which sets NODATACOW and no compression
#     itself -- it exists precisely so nobody has to remember chattr +C
#
# Needs btrfs-progs >= 5.15 for mkswapfile. Measured here: v7.1.

set -euo pipefail

SIZE="8G"
REMOVE=0
MOUNT="/swap"
SWAPFILE="/swap/swapfile"
SUBVOL="@swap"
PRIORITY=10

while (( $# )); do
    case "$1" in
        --size|-s) SIZE="${2:?--size needs a value, e.g. 8G}"; shift 2 ;;
        --remove)  REMOVE=1; shift ;;
        -h|--help) sed -n '3,8p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

(( EUID == 0 )) || { echo "setup-swapfile: needs root (sudo $0)" >&2; exit 1; }

note() { printf ':: %s\n' "$*"; }

ROOT_DEV=$(findmnt -no SOURCE / | sed 's/\[.*//')
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
[[ "$(findmnt -no FSTYPE /)" == "btrfs" ]] || { echo "setup-swapfile: / is not btrfs" >&2; exit 1; }

# ── Remove ──────────────────────────────────────────────────────────────────
if (( REMOVE )); then
    swapoff "$SWAPFILE" 2>/dev/null || true
    # Leave the subvolume and the fstab mount alone; only the swap entry and
    # the file go. Re-running without --remove then costs one mkswapfile.
    if grep -qF "$SWAPFILE" /etc/fstab; then
        cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
        sed -i "\|^$SWAPFILE[[:space:]]|d" /etc/fstab
        note "removed the swap entry from /etc/fstab"
    fi
    rm -f -- "$SWAPFILE"
    note "removed $SWAPFILE -- zram swap is untouched"
    swapon --show
    exit 0
fi

command -v btrfs >/dev/null || { echo "setup-swapfile: btrfs-progs is needed" >&2; exit 1; }

# ── The @swap subvolume ─────────────────────────────────────────────────────
# Created from the filesystem's TOP LEVEL (subvolid=5), not from inside /,
# so it is a sibling of @ and @home rather than a child of @ -- a child of @
# would be captured by every snapper snapshot, which is the thing to avoid.
if ! findmnt -no TARGET "$MOUNT" >/dev/null 2>&1; then
    top=$(mktemp -d)
    mount -o subvolid=5 "$ROOT_DEV" "$top"
    if [[ ! -d "$top/$SUBVOL" ]]; then
        btrfs subvolume create "$top/$SUBVOL" >/dev/null
        note "created subvolume $SUBVOL (sibling of @ -- snapper will not touch it)"
    else
        note "subvolume $SUBVOL already exists"
    fi
    umount "$top"; rmdir "$top"

    mkdir -p "$MOUNT"
    if ! grep -qE "^UUID=$ROOT_UUID[[:space:]]+$MOUNT[[:space:]]" /etc/fstab; then
        cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
        printf 'UUID=%-37s %-14s %-7s %s 0 0\n' \
            "$ROOT_UUID" "$MOUNT" "btrfs" "subvol=/$SUBVOL,defaults,noatime" >> /etc/fstab
        note "added $MOUNT to /etc/fstab (backup taken)"
    fi
    mount "$MOUNT"
fi
note "$MOUNT is mounted"

# ── The swapfile ────────────────────────────────────────────────────────────
if [[ -f "$SWAPFILE" ]]; then
    note "$SWAPFILE already exists ($(du -h "$SWAPFILE" | cut -f1)) -- leaving it alone"
else
    note "creating $SWAPFILE ($SIZE, NODATACOW + uncompressed via mkswapfile)"
    btrfs filesystem mkswapfile --size "$SIZE" --uuid clear "$SWAPFILE"
    chmod 600 "$SWAPFILE"
fi

# ── fstab + activate ────────────────────────────────────────────────────────
if ! grep -qE "^$SWAPFILE[[:space:]]" /etc/fstab; then
    cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    printf '%-46s %-14s %-7s %s 0 0\n' \
        "$SWAPFILE" "none" "swap" "defaults,pri=$PRIORITY" >> /etc/fstab
    note "added the swapfile to /etc/fstab at priority $PRIORITY (zram stays at 100)"
fi

swapon --all 2>/dev/null || true
if ! swapon --show=NAME --noheadings | grep -qF "$SWAPFILE"; then
    swapon --priority "$PRIORITY" "$SWAPFILE"
fi

echo
note "swap now:"
swapon --show
echo
note "zram is priority 100 and gets used first; this file only catches the overflow."
note "Undo:  sudo $0 --remove"
