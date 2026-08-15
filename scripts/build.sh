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

# --- Options ----------------------------------------------------------------
# By default the kernel is rebuilt with --force every run, so a changed hardening
# fragment can never be silently ignored. That costs a full kernel build (hours
# under emulation) even when you only changed the rootfs or UI, so --no-kernel-force
# hands the decision to pmbootstrap, which rebuilds only when the recipe changed.
#
# It is opt-in rather than the default because a stale kernel here means an
# UNHARDENED image — the one failure this project cannot ship. If you use it,
# run scripts/verify-disabled.sh afterwards: it reads the compiled .config and
# fails if a symbol you disabled isn't actually off.
kernel_force=1
install_password=""
usage() {
    cat <<EOF
usage: build.sh [--no-kernel-force] [--password PW]

  --no-kernel-force  Skip the forced kernel rebuild; let pmbootstrap decide
                     whether the cached kernel .apk is still current. Much
                     faster when iterating on non-kernel steps. Verify with
                     scripts/verify-disabled.sh before trusting the image.

  --password PW      Login password for the 'user' account. Without it,
                     'pmbootstrap install' PROMPTS interactively — and it does so
                     *after* the kernel build, so an unattended run stalls at the
                     ~45-minute mark. NOTE: this lands in your shell history and
                     is visible in 'ps'; use it for throwaway test images, not
                     for anything real.
EOF
}
while [ $# -gt 0 ]; do
    case "$1" in
        --no-kernel-force) kernel_force=0; shift ;;
        --password) install_password="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done

config_env="$repo_root/config/build.env"
fragment_file="$repo_root/config/disabled-subsystems.fragment"

# Wall-clock start for the timing summary printed at the end. Build duration is
# the metric this project keeps having to reason about (emulated vs cross-native
# is a 2x+ difference), so every run reports it per phase rather than leaving it
# to be reconstructed from log timestamps afterwards.
script_start=$(date +%s)
kernel_elapsed=0
install_elapsed=0
export_elapsed=0

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
# Declared explicitly so the channel is a decision, not a side effect of the UI.
: "${SYSTEMD:=always}"
# Diagnostics: sample the build's execution mode (see scripts/binfmt-watchdog.sh).
: "${BUILD_DIAGNOSTICS:=1}"
: "${BINFMT_WATCHDOG_HEAL:=0}"

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
systemd = $SYSTEMD

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

# --- 6b. Fast-route preflight: require the F-flagged qemu binfmt -------------
# crossdirect only uses the native cross-compiler when the aarch64 qemu binfmt
# entry has the F (fix-binary) flag. Without it the build silently degrades to
# full QEMU emulation and takes hours instead of minutes. Skipped on a native
# aarch64 host (e.g. the arm64 CI runner), where there is no emulation and no
# binfmt to check.
#
# The catch: `pmbootstrap init` above cleans up any leftover dirty chroot, and
# that teardown UNREGISTERS the F-flagged entry (it runs `echo -1 > .../qemu-*`
# for every arch). So on the very run that recovers from an interrupted build,
# the entry is gone by the time we get here even if it was correct beforehand.
# Rather than erroring and making the user re-register by hand, self-heal: if the
# host has the static qemu, re-register the F entry with fix-binfmt.sh, then
# re-check. Only fail if healing isn't possible or didn't take.
if [ "$ARCH" != "$(uname -m)" ]; then
    binfmt_entry=/proc/sys/fs/binfmt_misc/qemu-aarch64
    qemu_static=/usr/bin/qemu-aarch64-static
    if ! binfmt_has_f "$binfmt_entry"; then
        log "qemu-aarch64 binfmt not usable (missing, or no F flag) — attempting auto-heal"
        if [ -x "$qemu_static" ]; then
            if [ "$(id -u)" = 0 ]; then
                sh "$script_dir/fix-binfmt.sh" || true
            elif command -v sudo >/dev/null 2>&1; then
                sudo sh "$script_dir/fix-binfmt.sh" || true
            else
                log "cannot auto-heal: not running as root and sudo is unavailable"
            fi
        else
            log "cannot auto-heal: $qemu_static not found (install qemu-user-static)"
        fi
    fi
    if ! binfmt_has_f "$binfmt_entry"; then
        if [ -e "$binfmt_entry" ]; then
            log "qemu-aarch64 binfmt is registered WITHOUT the F (fix-binary) flag."
            log "crossdirect would fall back to slow full emulation (hours, not minutes)."
            log "Fix:  sudo sh $script_dir/fix-binfmt.sh"
            die "fast-route preflight failed (binfmt has no F flag)"
        else
            log "no qemu-aarch64 binfmt entry found — foreign-arch builds cannot run."
            log "Install the emulator:  sudo apt-get install -y qemu-user-static binfmt-support"
            log "(or re-run scripts/setup.sh), then verify:  cat $binfmt_entry"
            die "fast-route preflight failed (no qemu-aarch64 binfmt)"
        fi
    fi
    log "crossdirect preflight OK: qemu-aarch64 binfmt has the F flag"
fi

# --- 6c. Record the facts that explain build duration -----------------------
# A slow kernel build has several possible causes that look identical from the
# outside (emulation / too few jobs / the emulated-glue tax). Log the inputs now
# so the elapsed time at the end can actually be interpreted.
diag_log="$repo_root/$OUTPUT_DIR/build-diagnostics.log"
mkdir -p "$repo_root/$OUTPUT_DIR"
# Rotate rather than append: the summary below greps this file, and samples left
# over from an earlier build would be counted as if they belonged to this one.
if [ -f "$diag_log" ]; then
    mv -f "$diag_log" "$diag_log.prev"
fi

log "Host: $(nproc 2>/dev/null || echo '?') cpus, $(uname -m), kernel $(uname -r)"
free -h 2>/dev/null | while IFS= read -r line; do log "  mem: $line"; done

work_dir=$(pmbootstrap config work 2>/dev/null | tr -d '\r' || true)
if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
    log "pmbootstrap work dir: $work_dir"
    df -h "$work_dir" 2>/dev/null | while IFS= read -r line; do log "  disk: $line"; done

    # abuild's JOBS/MAKEFLAGS decide how wide the kernel build actually runs.
    # If this says JOBS=1 the build is serialized and no binfmt fix will help.
    abuild_conf="$work_dir/chroot_native/etc/abuild.conf"
    if [ -f "$abuild_conf" ]; then
        grep -E '^(JOBS|MAKEFLAGS)=' "$abuild_conf" 2>/dev/null \
            | while IFS= read -r line; do log "  abuild: $line"; done
    else
        log "  abuild: $abuild_conf not present yet (chroot not initialized)"
    fi

    # A warm ccache makes a build finish fast for reasons unrelated to
    # crossdirect — note it so timings are not compared across different states.
    ccache_dir="$work_dir/cache_ccache_$ARCH"
    if [ -d "$ccache_dir" ]; then
        log "  ccache: $(du -sh "$ccache_dir" 2>/dev/null | cut -f1) at $ccache_dir"
    else
        log "  ccache: cold (no $ccache_dir)"
    fi
fi

# --- 7. Build the kernel, install the rootfs, export the image --------------
# Start the execution-mode watchdog for the kernel build only — that is the step
# whose duration is in question, and the only one long enough to sample.
watchdog_pid=""
stop_watchdog() {
    if [ -n "$watchdog_pid" ]; then
        kill "$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
        watchdog_pid=""
    fi
}
# build.sh runs under `set -e`, so a failure mid-build must still reap the
# background sampler rather than orphaning it.
trap stop_watchdog EXIT INT TERM

if [ "$BUILD_DIAGNOSTICS" = "1" ]; then
    watchdog_args="--log $diag_log --parent $$"
    # NOT `[ ... ] && x=y` — under `set -e` a false test would abort the build.
    if [ "$BINFMT_WATCHDOG_HEAL" = "1" ]; then
        watchdog_args="$watchdog_args --heal"
    fi
    # shellcheck disable=SC2086
    sh "$script_dir/binfmt-watchdog.sh" $watchdog_args &
    watchdog_pid=$!
    log "Execution-mode watchdog running (pid $watchdog_pid) -> $diag_log"
fi

kernel_start=$(date +%s)
if [ "$kernel_force" = "1" ]; then
    log "Building the hardened kernel ($KERNEL_PKG) — forced full rebuild"
    pmbootstrap --details-to-stdout build --force "$KERNEL_PKG"
else
    log "Building the hardened kernel ($KERNEL_PKG) — cache allowed (--no-kernel-force)"
    log "  NOTE: run scripts/verify-disabled.sh afterwards to confirm the kernel"
    log "        actually carries your disables and wasn't served stale from cache."
    pmbootstrap --details-to-stdout build "$KERNEL_PKG"
fi
kernel_elapsed=$(( $(date +%s) - kernel_start ))
log "Kernel build finished in $(fmt_duration "$kernel_elapsed")"

stop_watchdog

# Record WHERE the package landed. The channel is part of the path, and a build
# that lands in a different channel than `install` reads from is invisible
# otherwise — apk just quietly prefers the repo's copy.
if [ -n "$work_dir" ] && [ -d "$work_dir/packages" ]; then
    find "$work_dir/packages" -name "$KERNEL_PKG-*.apk" 2>/dev/null \
        | while IFS= read -r apk; do log "built package: $apk"; done
fi

# Summarize what the watchdog saw, so the verdict is in the build log itself and
# not only in a file someone has to remember to open.
if [ "$BUILD_DIAGNOSTICS" = "1" ] && [ -f "$diag_log" ]; then
    emul_samples=$(grep -c 'cc1_emul=[1-9]' "$diag_log" 2>/dev/null || true)
    # Count sample lines whose binfmt token lacks an F. Covers BOTH failure
    # modes: the entry vanishing (ABSENT) and it being re-registered without the
    # flag (e.g. "OC") — the latter is what pmbootstrap's own fallback does.
    noF_samples=$(grep '  cc1=' "$diag_log" 2>/dev/null \
        | grep -vc 'binfmt=[A-Za-z]*F' || true)
    max_cc1=$(sed -n 's/.*  cc1=\([0-9]*\) .*/\1/p' "$diag_log" 2>/dev/null \
        | sort -n | tail -1)
    log "Diagnostics: samples with emulated cc1=${emul_samples:-0}, binfmt missing=${noF_samples:-0}, peak concurrent cc1=${max_cc1:-0}"
    if [ "${emul_samples:-0}" != "0" ]; then
        log "  VERDICT: cc1 ran under QEMU — crossdirect was NOT active (see $diag_log)"
    elif [ "${max_cc1:-0}" -le 2 ] 2>/dev/null; then
        log "  VERDICT: build never exceeded ${max_cc1:-0} concurrent compilers — under-parallelized, check abuild JOBS"
    else
        log "  VERDICT: compiler ran native and parallel — remaining time is emulated glue (fixdep/make/ld), not crossdirect"
    fi
fi

log "Installing the rootfs"
install_start=$(date +%s)
if [ -n "$install_password" ]; then
    pmbootstrap --details-to-stdout install --password "$install_password"
else
    log "NOTE: no --password given; pmbootstrap will prompt interactively here."
    pmbootstrap --details-to-stdout install
fi
install_elapsed=$(( $(date +%s) - install_start ))
log "Install finished in $(fmt_duration "$install_elapsed")"

# --- 7b. Prove the rootfs got OUR kernel, not the stock one -----------------
# apk installs the highest version available. If the binary repo ships a newer
# linux-rpi than this recipe builds — or if the build and install ran on
# different channels, so the local package sits in a packages/<channel>/ dir
# that install never looks in — apk silently substitutes upstream's kernel and
# reports success. That happened on 2026-08-03: the Pi booted a stock 6.18.41-r0
# with wireless/BT/sound fully ENABLED while the hardened 6.18.35-r0 sat unused
# in packages/edge/. Nothing failed; the image was simply not hardened.
#
# So compare what the rootfs actually installed against what the recipe declares.
want_ver=$(awk -F= '/^pkgver=/ { v=$2 } /^pkgrel=/ { r=$2 } END { print v "-r" r }' \
    "$overlay_dst/APKBUILD")
rootfs_db="$work_dir/chroot_rootfs_$DEVICE/lib/apk/db/installed"
if [ -f "$rootfs_db" ]; then
    got_ver=$(awk -v pkg="$KERNEL_PKG" '
        $0 == "P:" pkg { found=1; next }
        found && /^V:/ { sub(/^V:/, ""); print; exit }
    ' "$rootfs_db")
    log "kernel in rootfs: ${got_ver:-<none>} (recipe declares: $want_ver)"
    if [ -z "$got_ver" ]; then
        die "$KERNEL_PKG is not installed in the rootfs at all"
    elif [ "$got_ver" != "$want_ver" ]; then
        log "The rootfs has $KERNEL_PKG $got_ver but this recipe builds $want_ver."
        log "apk chose a different package — the image is NOT running your kernel,"
        log "so none of the hardening in config/disabled-subsystems.fragment applies."
        log "Fixes: raise pkgrel in kernel/$KERNEL_PKG/APKBUILD so it outranks the"
        log "repo, and confirm the build and install used the SAME channel"
        log "(local package must be under \$work/packages/<channel>/$ARCH/)."
        die "kernel substitution detected"
    fi
    log "OK: the rootfs is running the locally built hardened kernel"
else
    log "WARNING: cannot verify the installed kernel — $rootfs_db not found"
fi

log "Exporting the image"
mkdir -p "$repo_root/$OUTPUT_DIR"
export_start=$(date +%s)
pmbootstrap --details-to-stdout export "$repo_root/$OUTPUT_DIR"
export_elapsed=$(( $(date +%s) - export_start ))

# --- 8. Timing summary ------------------------------------------------------
total_elapsed=$(( $(date +%s) - script_start ))
log "================ TIMING ================"
log "  kernel  : $(fmt_duration "$kernel_elapsed")"
log "  install : $(fmt_duration "$install_elapsed")"
log "  export  : $(fmt_duration "$export_elapsed")"
log "  TOTAL   : $(fmt_duration "$total_elapsed")"
log "========================================"
# Reference points, so a slow run is recognizable as slow without digging:
#   kernel ~2h17m  = fully QEMU-emulated (the pre-pmb:cross-native baseline)
#   kernel ~40-75m = native cross-compile on this 6-core VM (expected)
log "  (kernel reference: ~40-75m native on 6 cores; ~2h17m means it was emulated)"

log "BUILD COMPLETE — see $repo_root/$OUTPUT_DIR"
log "To flash directly to a CM5: pmbootstrap install --sdcard=/dev/sdX  (replace sdX!)"
ls -la "$repo_root/$OUTPUT_DIR" || true
