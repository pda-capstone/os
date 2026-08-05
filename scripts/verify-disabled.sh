#!/bin/sh
#
# verify-disabled.sh — check that every subsystem in the fragment is really OFF.
#   1. The recipe input: our injected "CONFIG_X=n" lines in the staged
#      linux-rpi common-changes.config. Confirms the fragment was applied.
#   2. proof: the ".config" the kernel was actually compiled with.
#      This catches the case where "make olddefconfig" turned a symbol back on
#      because something else in the kernel selects it.
#
# Exits non-zero if any listed symbol is still enabled.
#
# Usage: verify-disabled.sh   (reads config/build.env and the fragment)

set -eu

LOG_TAG="verify"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$script_dir/lib.sh"

fragment_file="$repo_root/config/disabled-subsystems.fragment"
config_env="$repo_root/config/build.env"

if [ ! -f "$fragment_file" ]; then
    die "fragment file not found: $fragment_file"
fi

# Load the pins so we know the kernel package name.
if [ -f "$config_env" ]; then
    set -a
    . "$config_env"
    set +a
fi
: "${KERNEL_PKG:=linux-rpi}"

symbols=$(parse_disabled_symbols "$fragment_file")
if [ -z "$symbols" ]; then
    log "No subsystems listed in the fragment — nothing to verify."
    exit 0
fi

# is_disabled <config_file> <symbol>
# Succeeds (returns 0) when the symbol is OFF. A symbol counts as ON only if
# there is an active "CONFIG_X=y" or "CONFIG_X=m" line.
is_disabled() {
    config_file="$1"
    symbol="$2"
    if grep -Eq "^$symbol=[ymM]" "$config_file"; then
        return 1    # still enabled
    fi
    return 0        # =n, "is not set", or absent -> disabled
}

failed=0

# check_config_file <config_file> <label>
# Reports each symbol and records a failure (in $failed) for any still enabled.
check_config_file() {
    config_file="$1"
    label="$2"

    log "Checking $label: $config_file"
    for symbol in $symbols; do
        if is_disabled "$config_file" "$symbol"; then
            log "  ok   $symbol"
        else
            log "  FAIL $symbol is still enabled"
            failed=1
        fi
    done
}

work_dir=$(pmbootstrap config work 2>/dev/null | tr -d '\r' || true)

# --- Layer 1: our injected recipe input (confirms the fragment was applied) --
# The staged recipe lives in pmaports temp/. Its common-changes.config should
# now contain "CONFIG_X=n" for each symbol.
changes_file=""
if [ -n "$work_dir" ]; then
    changes_file="$work_dir/cache_git/pmaports/temp/$KERNEL_PKG/common-changes.config"
fi
if [ -n "$changes_file" ] && [ -f "$changes_file" ]; then
    log "Checking recipe input: $changes_file"
    for symbol in $symbols; do
        if grep -Eq "^$symbol=n$" "$changes_file"; then
            log "  ok   $symbol=n present"
        else
            log "  FAIL $symbol=n missing from recipe"
            failed=1
        fi
    done
else
    log "Note: staged recipe not found; skipping recipe-input check."
fi

# --- Layer 2: the .config the kernel was actually compiled with -------------
# The Alpine recipe builds in "build-<flavor>.<carch>/.config"; the -dev
# subpackage also ships a ".config" under usr/src/linux-headers-*.
built_config=""
if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
    built_config=$(find "$work_dir" \
        \( -path '*build-rpi*/.config' -o -path '*linux-headers-*/.config' \) \
        -type f 2>/dev/null | head -n 1 || true)
fi

# --- Layer 2b: fall back to the config shipped inside the built .apk --------
# The build tree above is transient: abuild cleans it after packaging, and
# `pmbootstrap zap` deletes the whole chroot. So layer 2 usually finds nothing
# even right after a successful build, which is how this script came to report
# PASS on recipe input alone. The kernel package ships /boot/config-<ver>, which
# is the same data and persists in $work/packages/. Prefer it over giving up.
if [ -z "$built_config" ] && [ -n "$work_dir" ] && [ -d "$work_dir/packages" ]; then
    apk_file=$(find "$work_dir/packages" -name "$KERNEL_PKG-*.apk" 2>/dev/null \
        | sort | tail -n 1)
    if [ -n "$apk_file" ]; then
        # --ignore-zeros is REQUIRED. An .apk is three concatenated gzip streams
        # (signature, control, data), each its own tar archive. Without it, tar
        # stops at the first end-of-archive marker and sees only the .SIGN.* file
        # — the package looks empty and this fallback silently finds nothing.
        #
        # Resolve the exact member name first rather than relying on GNU tar's
        # --wildcards for in-archive globbing.
        member=$(tar --ignore-zeros -tzf "$apk_file" 2>/dev/null \
            | grep -m1 '^boot/config-' || true)
        if [ -n "$member" ]; then
            extracted="${TMPDIR:-/tmp}/verify-disabled.$$.config"
            if tar --ignore-zeros -xzOf "$apk_file" "$member" > "$extracted" 2>/dev/null &&
               [ -s "$extracted" ]; then
                built_config="$extracted"
                log "Build tree absent; using $member from $(basename "$apk_file")"
            else
                rm -f "$extracted"
                log "NOTE: found $member in $(basename "$apk_file") but could not extract it"
            fi
        else
            log "NOTE: $(basename "$apk_file") contains no boot/config-* member"
        fi
    fi
fi

inconclusive=0
if [ -n "$built_config" ]; then
    check_config_file "$built_config" "compiled kernel .config"
else
    inconclusive=1
    log "WARNING: compiled kernel .config not found — has the kernel been built?"
    log "         (It also lives inside the build chroot, so 'pmbootstrap zap' removes it.)"
fi

# --- Verdict ----------------------------------------------------------------
if [ "$failed" -ne 0 ]; then
    die "One or more subsystems are still enabled (see the FAIL lines above)."
fi

# Layer 1 alone is NOT proof. It only shows the fragment was written into the
# recipe; it says nothing about what `make olddefconfig` did afterwards, and this
# project has already been burned twice by that gap:
#   - CONFIG_WIRELESS=n was in the recipe and olddefconfig re-enabled the stack
#     anyway, because WLAN drivers `select CFG80211`.
#   - On 2026-08-03 this script printed PASS for a kernel that was never even
#     installed (apk had silently substituted the stock build).
# So refuse to claim PASS when the authoritative layer could not be read.
if [ "$inconclusive" -ne 0 ]; then
    log "INCONCLUSIVE — the recipe asks for every symbol to be disabled, but the"
    log "               compiled .config could not be read, so this is NOT proof."
    log "               Verify on the running device instead:"
    log "                 grep -E '^CONFIG_(WIRELESS|WLAN|CFG80211|MAC80211|BT|SOUND)=' /boot/config-\$(uname -r)"
    log "                 uname -r    # must match this recipe's pkgver-pkgrel"
    exit 2
fi

log "PASS — every listed subsystem is disabled (verified against the compiled .config)."
