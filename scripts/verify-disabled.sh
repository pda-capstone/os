#!/bin/sh
#
# Checks that everything in disabled-subsystems.fragment is actually off:
#   1. the recipe got the CONFIG_X=n lines
#   2. the compiled .config still has them off (olddefconfig can flip a symbol
#      back on if something else in the tree selects it)
#
# Exits non-zero if anything's still enabled.

set -eu

LOG_TAG="verify"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$script_dir/lib.sh"

fragment_file="$repo_root/config/disabled-subsystems.fragment"
: "${KERNEL_PKG:=linux-rpi}"

if [ ! -f "$fragment_file" ]; then
    die "fragment file not found: $fragment_file"
fi

symbols=$(parse_disabled_symbols "$fragment_file")
if [ -z "$symbols" ]; then
    log "No subsystems listed in the fragment — nothing to verify."
    exit 0
fi

is_disabled() {
    config_file="$1"
    symbol="$2"
    if grep -Eq "^$symbol=[ymM]" "$config_file"; then
        return 1
    fi
    return 0
}

failed=0

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

# recipe input
changes_file=""
if [ -n "$work_dir" ]; then
    changes_file="$work_dir/cache_git/pmaports/device/downstream/$KERNEL_PKG/common-changes.config"
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

# compiled config
built_config=""
if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
    built_config=$(find "$work_dir" \
        \( -path '*build-rpi*/.config' -o -path '*linux-headers-*/.config' \) \
        -type f 2>/dev/null | head -n 1 || true)
fi

# fall back to the config shipped in the built apk (build tree gets cleaned
# after packaging, so the above usually finds nothing)
if [ -z "$built_config" ] && [ -n "$work_dir" ] && [ -d "$work_dir/packages" ]; then
    apk_file=$(find "$work_dir/packages" -name "$KERNEL_PKG-[0-9]*.apk" 2>/dev/null \
        | sort | tail -n 1)
    if [ -n "$apk_file" ]; then
        # apk = 3 concatenated gzip streams, need --ignore-zeros or tar stops early
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
fi

if [ "$failed" -ne 0 ]; then
    die "One or more subsystems are still enabled (see the FAIL lines above)."
fi

if [ "$inconclusive" -ne 0 ]; then
    log "INCONCLUSIVE — fragment looks right but the compiled config couldn't be read."
    log "Check on-device instead:"
    log "  grep -E '^CONFIG_(BT|MODVERSIONS|SOUND)=' /boot/config-\$(uname -r)"
    log "  uname -r    # must match this recipe's pkgver-pkgrel"
    exit 2
fi

log "PASS — every listed subsystem is disabled (verified against the compiled .config)."
