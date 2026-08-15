#!/bin/sh
#
# boot-test.sh — DEFERRED / STUB (the "boot test" validation from the plan).
#
# The target is a real Raspberry Pi CM5, which can't be reliably booted inside
# the x86 CI runner, so this check isn't part of the pipeline yet. For now the
# script just explains the plan and exits successfully (a skip) unless you set
# BOOT_TEST=1.
#
# To enable it later:
#   1. Register a physical CM5 as a GitHub self-hosted runner (label: cm5).
#   2. Add a "boot-test" job in .github/workflows/build.yml that:
#        - runs on that self-hosted runner
#        - downloads the image artifact from the build job
#        - flashes it to the CM5 (eMMC via rpiboot, or an SD/NVMe)
#        - power-cycles the board and reads the serial console
#        - checks the boot log reaches the login prompt within a timeout
#   3. Implement that flash + serial logic below, guarded by BOOT_TEST=1.

set -eu

LOG_TAG="boot-test"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/lib.sh"

if [ "${BOOT_TEST:-0}" != "1" ]; then
    log "SKIPPED — the boot test needs a real CM5 board and is deferred."
    log "Set BOOT_TEST=1 and run on a self-hosted CM5 runner to enable it."
    exit 0
fi

die "BOOT_TEST=1 was set, but the hardware boot logic isn't implemented yet.
See the top of this file for the steps to add it."
