#!/bin/sh
#
# lib.sh — small helpers shared by the build scripts.
# This file is meant to be sourced (". lib.sh"), not run on its own.

log() {
    printf '[%s] %s\n' "${LOG_TAG:-pmos}" "$*" >&2
}

# Print an error message and stop the whole script.
die() {
    printf '[%s] ERROR: %s\n' "${LOG_TAG:-pmos}" "$*" >&2
    exit 1
}

# Format a duration in seconds as human-readable text.
# Drops the hours field below an hour so short builds read cleanly.
#
# Usage: fmt_duration <seconds>     e.g. 2472 -> "41m 12s", 8247 -> "2h 17m 27s"
fmt_duration() {
    _t="${1:-0}"
    if [ "$_t" -ge 3600 ]; then
        printf '%dh %dm %ds' $(( _t / 3600 )) $(( (_t % 3600) / 60 )) $(( _t % 60 ))
    else
        printf '%dm %ds' $(( _t / 60 )) $(( _t % 60 ))
    fi
}

# Return 0 if the aarch64 qemu binfmt_misc entry is registered WITH the F
# (fix-binary) flag, 1 otherwise (entry missing, or present but no F).
#
# crossdirect only uses the native cross-compiler when this flag is set; without
# it the build silently falls back to slow full QEMU emulation. On Debian/Ubuntu
# the qemu-user-static package sets the F flag up for us.
#
# Usage: binfmt_has_f [entry_path]   (defaults to the qemu-aarch64 entry)
binfmt_has_f() {
    entry="${1:-/proc/sys/fs/binfmt_misc/qemu-aarch64}"
    [ -e "$entry" ] || return 1
    grep -q '^flags:.*F' "$entry"
}

# Read a kernel-config fragment and print the name of every symbol it asks us
# to DISABLE, one per line.
#
# It understands the two ways of writing "off":
#     # CONFIG_FOO is not set
#     CONFIG_FOO=n
# Blank lines, ordinary comments, and "=y"/"=m" lines are ignored.
#
# Usage: parse_disabled_symbols <fragment_file>
parse_disabled_symbols() {
    fragment_file="$1"

    # Read the file one line at a time. The "|| [ -n "$line" ]" part makes sure
    # we still process the final line if the file has no trailing newline.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "# CONFIG_"*"is not set"*)
                # "# CONFIG_BT is not set" — split into words; the second
                # word ("CONFIG_BT") is the symbol name.
                # shellcheck disable=SC2086
                set -- $line
                printf '%s\n' "$2"
                ;;
            CONFIG_*=n | CONFIG_*=N)
                # e.g. "CONFIG_SOUND=n" — drop everything from the "=" onward.
                printf '%s\n' "${line%%=*}"
                ;;
            *)
                # Not a disable directive; skip it.
                ;;
        esac
    done < "$fragment_file"
}
