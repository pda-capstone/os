#!/bin/sh
#
# build.sh (native Linux) — build the hardened postmarketOS image for the CM5.
#
# Runs pmbootstrap DIRECTLY on a Linux host (no Docker). Install pmbootstrap and
# its host tools first with scripts/setup.sh. Steps:
#   1. load the pins from config/build.env
#   2. configure pmbootstrap with no interactive prompts
#   3. stage our vendored linux-rpi recipe and inject the disable fragment
#   4. compile the hardened kernel, install the rootfs, export the image
set -eu

LOG_TAG="build"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$script_dir/lib.sh"

config_env="$repo_root/config/build.env"
fragment_file="$repo_root/config/disabled-subsystems.fragment"

if [ ! -f "$config_env" ]; then
    die "missing $config_env"
fi
if [ ! -f "$fragment_file" ]; then
    die "missing $fragment_file"
fi

# --- 1. Load the pins -------------------------------------------------------
set -a
. "$config_env"
set +a

if [ -z "${DEVICE:-}" ]; then
    die "DEVICE is not set in build.env"
fi
if [ -z "${ARCH:-}" ]; then
    die "ARCH is not set in build.env"
fi
: "${UI:=none}"
: "${OUTPUT_DIR:=out}"

if ! command -v pmbootstrap >/dev/null 2>&1; then
    die "pmbootstrap not found on PATH — run scripts/setup.sh first (and make sure ~/.local/bin is on PATH)"
fi

log "device=$DEVICE arch=$ARCH ui=$UI release=${PMOS_RELEASE:-unset}"
if [ -z "${PMAPORTS_REF:-}" ]; then
    log "WARNING: PMAPORTS_REF is empty — the build is NOT reproducible."
    log "         Pin a pmaports commit in config/build.env."
fi

# --- 2. Pick a reproducible timestamp ---------------------------------------
if command -v git >/dev/null 2>&1 && git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    SOURCE_DATE_EPOCH=$(git -C "$repo_root" log -1 --pretty=%ct)
else
    SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1704067200}   # 2024-01-01
fi
export SOURCE_DATE_EPOCH
log "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"

# --- 3. Configure pmbootstrap without prompts -------------------------------
# Write the config file directly, then run init reading these as defaults.
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
config_file="$config_dir/pmbootstrap_v3.cfg"
log "Writing $config_file (device=$DEVICE ui=$UI)"
mkdir -p "$config_dir"
cat > "$config_file" <<EOF
[pmbootstrap]
device = $DEVICE
ui = $UI

[providers]
EOF

# Self-heal: init only clones pmaports when the directory is ABSENT. Remove an
# incomplete checkout (no pmaports.cfg) so init re-clones instead of erroring.
stale_aports="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
if [ -d "$stale_aports" ] && [ ! -f "$stale_aports/pmaports.cfg" ]; then
    log "Removing incomplete pmaports checkout at $stale_aports"
    rm -rf "$stale_aports"
fi

# "yes ''" accepts every default (our config values); "-y" auto-confirms yes/no
# prompts (incl. the downstream-kernel warning that otherwise loops).
log "Running pmbootstrap init (non-interactive)"
yes '' | pmbootstrap --details-to-stdout -y init

# --- 4. Locate pmaports -----------------------------------------------------
aports_dir=$(pmbootstrap config aports | tr -d '\r')
if [ -z "$aports_dir" ] || [ ! -d "$aports_dir" ]; then
    die "could not find the pmaports directory (got: '$aports_dir')"
fi
log "pmaports is at $aports_dir"

# Report the exact pmaports commit actually checked out, so the build log records
# what it was built against even when PMAPORTS_REF is empty (non-reproducible).
if git -C "$aports_dir" rev-parse --git-dir >/dev/null 2>&1; then
    pmaports_commit=$(git -C "$aports_dir" rev-parse HEAD)
    if git -C "$aports_dir" diff --quiet 2>/dev/null && \
       git -C "$aports_dir" diff --cached --quiet 2>/dev/null; then
        pmaports_state=clean
    else
        pmaports_state=dirty
    fi
    log "pmaports commit=$pmaports_commit ($pmaports_state)"
    if [ -n "${PMAPORTS_REF:-}" ] && [ "$pmaports_commit" != "$PMAPORTS_REF" ]; then
        log "WARNING: checked-out pmaports commit does not match PMAPORTS_REF=$PMAPORTS_REF"
    fi
else
    log "WARNING: pmaports at $aports_dir is not a git checkout — cannot report its commit"
fi

# --- 5. Stage our custom linux-rpi recipe as an overlay ---------------------
: "${KERNEL_PKG:=linux-rpi}"
overlay_src="$repo_root/kernel/$KERNEL_PKG"
if [ ! -d "$overlay_src" ]; then
    die "vendored kernel recipe not found: $overlay_src"
fi
overlay_dst="$aports_dir/temp/$KERNEL_PKG"
log "Staging $KERNEL_PKG recipe into $overlay_dst"
rm -rf "$overlay_dst"
mkdir -p "$aports_dir/temp"
cp -r "$overlay_src" "$overlay_dst"

# --- 6. Disable the subsystems from the fragment ----------------------------
log "Injecting disable fragment into the kernel recipe"
sh "$script_dir/apply-fragment.sh" \
    "$overlay_dst/common-changes.config" "$fragment_file"

# Update ONLY the checksum of the file we edited; keep Alpine's known-good hashes
# for the kernel tarball/patches so abuild still verifies every download against
# a trusted hash (a tampered mirror fails the check and aborts).
log "Updating checksum for common-changes.config (upstream hashes preserved)"
new_sum=$(sha512sum "$overlay_dst/common-changes.config" | cut -d' ' -f1)
awk -v sum="$new_sum" '
    /  common-changes\.config$/ { print sum "  common-changes.config"; next }
    { print }
' "$overlay_dst/APKBUILD" > "$overlay_dst/APKBUILD.tmp"
mv "$overlay_dst/APKBUILD.tmp" "$overlay_dst/APKBUILD"
if ! grep -q "^${new_sum}  common-changes.config\$" "$overlay_dst/APKBUILD"; then
    die "failed to update common-changes.config checksum in the APKBUILD"
fi

# --- 7. Build the kernel, install the rootfs, export the image --------------
log "Building the hardened kernel ($KERNEL_PKG) — crossdirect makes this ~tens of minutes"
pmbootstrap --details-to-stdout build --force "$KERNEL_PKG"

log "Installing the rootfs"
pmbootstrap --details-to-stdout install

log "Exporting the image"
mkdir -p "$repo_root/$OUTPUT_DIR"
pmbootstrap --details-to-stdout export "$repo_root/$OUTPUT_DIR"

log "BUILD COMPLETE — see $repo_root/$OUTPUT_DIR"
log "To flash directly to a CM5: pmbootstrap install --sdcard=/dev/sdX  (replace sdX!)"
ls -la "$repo_root/$OUTPUT_DIR" || true
