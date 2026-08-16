#!/bin/sh
#
# Helpers shared by the build scripts. Source this file; don't run it.

log() {
    printf '[%s] %s\n' "${LOG_TAG:-pmos}" "$*" >&2
}

die() {
    printf '[%s] ERROR: %s\n' "${LOG_TAG:-pmos}" "$*" >&2
    exit 1
}

# Print the name of every symbol a fragment asks us to disable, one per line.
# Recognises both "# CONFIG_FOO is not set" and "CONFIG_FOO=n".
#
# Usage: parse_disabled_symbols <fragment_file>
parse_disabled_symbols() {
    fragment_file="$1"

    # The "|| [ -n ... ]" catches a final line with no trailing newline.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "# CONFIG_"*"is not set"*)
                # Word-split the line so $2 is the symbol name.
                set -- $line
                printf '%s\n' "$2"
                ;;
            CONFIG_*=n | CONFIG_*=N)
                printf '%s\n' "${line%%=*}"
                ;;
            *) ;;
        esac
    done < "$fragment_file"
}
