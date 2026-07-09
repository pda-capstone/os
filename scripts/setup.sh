#!/bin/sh
#
# setup.sh (native Linux) — install pmbootstrap and the host tools it needs.
#
# This replaces the Docker image from the Windows variant. Run it ONCE on your
# Linux machine before the first build. It:
#   1. installs host dependencies via your distro's package manager
#   2. clones pmbootstrap at the pinned version and links it onto your PATH
#
# Re-running is safe (idempotent).
set -eu

LOG_TAG="setup"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$script_dir/lib.sh"

# Pinned pmbootstrap version comes from the same config as the build.
set -a
# shellcheck disable=SC1091
. "$repo_root/config/build.env"
set +a
: "${PMBOOTSTRAP_VERSION:=3.10.3}"

# --- 1. Host dependencies ---------------------------------------------------
# pmbootstrap needs python3, git, and various disk/partition tools, plus
# qemu-user-static + binfmt to run aarch64 chroots on an x86 host.
install_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        log "Installing dependencies with apt"
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends \
            git python3 kpartx procps util-linux e2fsprogs dosfstools \
            parted xz-utils qemu-user-static binfmt-support
    elif command -v dnf >/dev/null 2>&1; then
        log "Installing dependencies with dnf"
        sudo dnf install -y \
            git python3 kpartx procps-ng util-linux e2fsprogs dosfstools \
            parted xz qemu-user-static
    elif command -v pacman >/dev/null 2>&1; then
        log "Installing dependencies with pacman"
        sudo pacman -Sy --needed --noconfirm \
            git python multipath-tools procps-ng util-linux e2fsprogs \
            dosfstools parted xz qemu-user-static-binfmt || \
            log "NOTE: install qemu-user-static from the AUR if the above failed"
    elif command -v zypper >/dev/null 2>&1; then
        log "Installing dependencies with zypper"
        sudo zypper install -y \
            git python3 kpartx procps util-linux e2fsprogs dosfstools \
            parted xz qemu-linux-user
    else
        log "WARNING: no known package manager found. Install these manually:"
        log "  git python3 kpartx procps util-linux e2fsprogs dosfstools parted xz qemu-user-static"
    fi
}
install_deps

# --- 2. pmbootstrap ---------------------------------------------------------
pmb_dir="$HOME/.local/opt/pmbootstrap"
bin_dir="$HOME/.local/bin"
mkdir -p "$bin_dir"

if [ -d "$pmb_dir/.git" ]; then
    log "Updating pmbootstrap checkout to $PMBOOTSTRAP_VERSION"
    git -C "$pmb_dir" fetch --tags --quiet
    git -C "$pmb_dir" checkout --quiet "$PMBOOTSTRAP_VERSION"
else
    log "Cloning pmbootstrap $PMBOOTSTRAP_VERSION"
    git clone --depth 1 --branch "$PMBOOTSTRAP_VERSION" \
        https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$pmb_dir"
fi

ln -sf "$pmb_dir/pmbootstrap.py" "$bin_dir/pmbootstrap"
log "Linked pmbootstrap -> $bin_dir/pmbootstrap"

# --- 3. PATH check ----------------------------------------------------------
case ":$PATH:" in
    *":$bin_dir:"*)
        log "Done. Try: pmbootstrap --version"
        ;;
    *)
        log "Done, but $bin_dir is not on your PATH."
        log "Add this to your ~/.profile (or ~/.bashrc / ~/.zshrc) and re-open your shell:"
        log "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac
