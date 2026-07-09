#!/bin/sh
#
# lib.sh — small helpers shared by the build scripts.
# This file is meant to be sourced (". lib.sh"), not run on its own.

# Print a status message. Goes to stderr so it never mixes into data that a
# caller captures with $(...). Set LOG_TAG in each script for a nice prefix.
log() {
    printf '[%s] %s\n' "${LOG_TAG:-pmos}" "$*" >&2
}

# Print an error message and stop the whole script.
die() {
    printf '[%s] ERROR: %s\n' "${LOG_TAG:-pmos}" "$*" >&2
    exit 1
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
                # e.g. "# CONFIG_BT is not set" — split into words; the second
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
