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

if [ -n "$built_config" ]; then
    check_config_file "$built_config" "compiled kernel .config"
else
    log "WARNING: compiled kernel .config not found — has the kernel been built?"
    log "         (Relying on the recipe-input check above only.)"
fi

# --- Verdict ----------------------------------------------------------------
if [ "$failed" -ne 0 ]; then
    die "One or more subsystems are still enabled (see the FAIL lines above)."
fi

log "PASS — every listed subsystem is disabled."
