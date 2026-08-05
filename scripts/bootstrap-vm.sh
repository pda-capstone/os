#!/bin/sh
#
# bootstrap-vm.sh — take a fresh Debian/Ubuntu VM from zero to build-ready.
#
# One command on a brand-new VM (installs git, clones, sets everything up):
#   curl -fsSL https://raw.githubusercontent.com/quinnwillett/pmos-hardened-linux/main/scripts/bootstrap-vm.sh | sh
#
# Or, if you've already cloned the repo:
#   sh scripts/bootstrap-vm.sh
#
# Pass --build to also kick off the first hardened image build once ready.
#
# It:
#   1. finds the repo (or clones it if you ran the curl one-liner)
#   2. installs pmbootstrap + host tools via setup.sh
#   3. confirms the crossdirect fast path (qemu-aarch64 binfmt F flag), and
#      self-heals with fix-binfmt.sh if the flag is missing
#   4. optionally starts the build
set -eu

REPO_URL="https://github.com/quinnwillett/pmos-hardened-linux.git"
REPO_DIR="${REPO_DIR:-$HOME/pmos-hardened-linux}"

DO_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --build) DO_BUILD=1 ;;
        *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

# --- 1. Locate or fetch the repo -------------------------------------------
# If this script lives inside a checkout (scripts/bootstrap-vm.sh), use it in
# place. Otherwise we were piped from curl — install git and clone.
if src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) \
   && [ -f "$src_dir/../config/build.env" ]; then
    repo_root=$(CDPATH= cd -- "$src_dir/.." && pwd)
else
    if ! command -v git >/dev/null 2>&1; then
        echo "[bootstrap] installing git"
        sudo apt-get update && sudo apt-get install -y git
    fi
    if [ -d "$REPO_DIR/.git" ]; then
        echo "[bootstrap] updating existing checkout at $REPO_DIR"
        git -C "$REPO_DIR" pull --ff-only
    else
        echo "[bootstrap] cloning into $REPO_DIR"
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    repo_root="$REPO_DIR"
fi

LOG_TAG="bootstrap"
# shellcheck disable=SC1091
. "$repo_root/scripts/lib.sh"

# --- 2. Install pmbootstrap + host tools -----------------------------------
log "Installing pmbootstrap + host tools (setup.sh)"
sh "$repo_root/scripts/setup.sh"

# setup.sh links pmbootstrap into ~/.local/bin; make sure it's usable right now.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
esac

# --- 3. Confirm the crossdirect fast path ----------------------------------
set -a
# shellcheck disable=SC1091
. "$repo_root/config/build.env"
set +a

if [ "${ARCH:-}" = "aarch64" ] && [ "$(uname -m)" != "aarch64" ]; then
    if binfmt_has_f; then
        log "OK: qemu-aarch64 binfmt has the F flag — crossdirect runs native."
    else
        log "qemu-aarch64 binfmt lacks the F flag; running fix-binfmt.sh"
        sudo sh "$repo_root/scripts/fix-binfmt.sh" || true
        if binfmt_has_f; then
            log "OK: F flag now present — crossdirect runs native."
        else
            die "Still no F flag; builds would emulate slowly. Fix before building."
        fi
    fi
else
    log "Native ${ARCH:-?} host — no emulation, crossdirect not needed."
fi

# --- 4. Ready (and maybe build) --------------------------------------------
log "Environment is build-ready."
if [ "$DO_BUILD" = "1" ]; then
    log "Starting build (scripts/build.sh)"
    sh "$repo_root/scripts/build.sh"
else
    log "Next:  cd $repo_root && sh scripts/build.sh"
fi
