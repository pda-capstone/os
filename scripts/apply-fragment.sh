#!/bin/sh
#
# apply-fragment.sh — inject our "disable" directives into the linux-rpi recipe
# Usage: apply-fragment.sh <common-changes.config> <fragment_file>

set -eu

LOG_TAG="apply-fragment"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/lib.sh"

changes_file=${1:-}
fragment_file=${2:-}

if [ -z "$changes_file" ] || [ -z "$fragment_file" ]; then
    die "usage: apply-fragment.sh <common-changes.config> <fragment_file>"
fi
if [ ! -f "$changes_file" ]; then
    die "config-changes file not found: $changes_file"
fi
if [ ! -f "$fragment_file" ]; then
    die "fragment file not found: $fragment_file"
fi

marker_begin="# >>> hardened-pmos disables (generated) >>>"
marker_end="# <<< hardened-pmos disables (generated) <<<"

# Work out which symbols to disable (parser lives in lib.sh).
symbols=$(parse_disabled_symbols "$fragment_file")

# Remove any previous generated block 
tmp="${changes_file}.tmp.$$"
awk -v b="$marker_begin" -v e="$marker_end" '
    $0 == b { skip = 1 }
    skip    { if ($0 == e) skip = 0; next }
    { print }
' "$changes_file" > "$tmp"
mv "$tmp" "$changes_file"

if [ -z "$symbols" ]; then
    log "No subsystems to disable in $fragment_file — nothing appended."
    exit 0
fi

# Append a fresh generated block: one "CONFIG_X=n" per symbol.
{
    printf '%s\n' "$marker_begin"
    for symbol in $symbols; do
        printf '%s=n\n' "$symbol"
    done
    printf '%s\n' "$marker_end"
} >> "$changes_file"

log "Appended disables to $changes_file:"
for symbol in $symbols; do
    log "  - $symbol=n"
done
