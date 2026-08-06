#!/bin/sh
#
# flash-sdcard.sh — write the hardened image straight to a real SD card/eMMC
# via `pmbootstrap install --sdcard=...`, after clearing a trap that this
# project hit in practice.
#
# THE TRAP: if an earlier `pmbootstrap install`/`export` ran against a LOOP
# device (an image-file build, e.g. `pmbootstrap export` -> out/raspberry-pi5.img),
# pmbootstrap creates /dev/installp{N} bind mounts in the native chroot pointing
# at that loop device's partitions. If those never get torn down (no `zap` in
# between) and you then run a `--sdcard` install, pmbootstrap's own
# partitions_mount() checks `ismount(/dev/installp{N})`, finds it ALREADY
# mounted (to the now-detached loop device), and silently skips rebinding it to
# the real card. `mkfs.ext4` then fails with "No such device or address" trying
# to size a device that no longer exists — not a flaw in the built image, just
# stale chroot state. See pmb/install/partition.py's bind_file().
#
# This script:
#   1. unmounts any partitions of the target card the desktop auto-mounted
#   2. unmounts any stale /dev/install* bind mounts left by a prior install
#   3. runs `pmbootstrap install --sdcard=...`
#
# Usage:
#   sh scripts/flash-sdcard.sh --sdcard /dev/mmcblk0 --password 'secret'
#
# Safety: refuses to run without an explicit --sdcard, refuses obvious host
# disks, and pmbootstrap itself still prompts "Are you sure you want to
# overwrite this disk?" before writing — this script does not bypass that.
set -eu

LOG_TAG="flash"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$script_dir/lib.sh"

sdcard=""
password=""
usage() {
    cat <<EOF
usage: flash-sdcard.sh --sdcard /dev/mmcblkX [--password PW]

  --sdcard DEV    Target block device (the WHOLE disk, e.g. /dev/mmcblk0, not
                   a partition like /dev/mmcblk0p1). Check with 'lsblk' first.

  --password PW   Login password for the 'user' account. Without it,
                   'pmbootstrap install' prompts interactively partway through.
                   NOTE: this lands in your shell history and is visible in
                   'ps'; use it for throwaway test images, not anything real.
EOF
}
while [ $# -gt 0 ]; do
    case "$1" in
        --sdcard) sdcard="${2:-}"; shift 2 ;;
        --password) password="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done

[ -n "$sdcard" ] || { usage >&2; die "--sdcard is required"; }
[ -b "$sdcard" ] || die "$sdcard is not a block device"

# Minimal guard against pointing this at an obvious host disk. Not exhaustive —
# `lsblk` before you run this is still on you.
case "$sdcard" in
    /dev/nvme*|/dev/sda)
        die "refusing to touch $sdcard -- looks like it could be a host system disk"
        ;;
esac

work_dir=$(pmbootstrap config work 2>/dev/null | tr -d '\r' || true)
[ -n "$work_dir" ] || die "'pmbootstrap config work' returned nothing -- run scripts/setup.sh first?"

log "Target: $sdcard"
log "pmbootstrap work dir: $work_dir"

# --- 1. Unmount any partitions of the target card that are currently mounted
#         (e.g. auto-mounted by the desktop when the card was inserted). -----
for part in "$sdcard"?*; do
    [ -b "$part" ] || continue
    mountpoint_path=$(findmnt -n -o TARGET "$part" 2>/dev/null || true)
    if [ -n "$mountpoint_path" ]; then
        log "Unmounting $part from $mountpoint_path"
        sudo umount "$part"
    fi
done

# --- 2. Clear stale /dev/install* bind mounts left by a prior install ------
# so pmbootstrap re-binds them to THIS card's real partitions instead of
# silently reusing dead ones (see the header comment).
native_dev="$work_dir/chroot_native/dev"
for name in install installp1 installp2 installp3; do
    target="$native_dev/$name"
    if mountpoint -q "$target" 2>/dev/null; then
        log "Unmounting stale $target"
        sudo umount "$target"
    fi
done

# --- 3. Run the real install -------------------------------------------------
log "Running: pmbootstrap install --sdcard=$sdcard"
if [ -n "$password" ]; then
    pmbootstrap --details-to-stdout install --sdcard="$sdcard" --password "$password"
else
    log "No --password given -- pmbootstrap will prompt interactively."
    pmbootstrap --details-to-stdout install --sdcard="$sdcard"
fi

log "Done. On the device, confirm the hardened kernel: uname -r must end -1-rpi (ours), not -0-rpi."
log "If this failed the SAME way again, the deeper reset is: pmbootstrap zap (chroots only, NOT -p/--packages), then retry."
