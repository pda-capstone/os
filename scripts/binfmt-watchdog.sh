#!/bin/sh
#
# binfmt-watchdog.sh — sample the build's execution mode while it runs.
#
# WHY THIS EXISTS
# ---------------
# A kernel build took 2h17m on a 6-core host where a correctly cross-compiled
# linux-rpi should take ~25-45 min. Three different causes fit that number and
# they need completely different fixes:
#
#   H1 emulation      — the F-flagged qemu binfmt entry gets destroyed mid-build
#                       (pmbootstrap's chroot teardown unregisters it), so
#                       crossdirect stops working and cc1 runs under QEMU.
#   H2 parallelism    — abuild's JOBS is misconfigured and the build isn't
#                       actually running 6-wide.
#   H3 emulated glue  — crossdirect only accelerates the COMPILER. fixdep runs
#                       once per translation unit, plus emulated make/sh/ld/
#                       modpost/depmod. That tax is real and unfixable on x86.
#
# build.sh's existing preflight proves the F flag is correct BEFORE the build
# starts, but nothing observes it during the hours that actually matter. This
# watchdog samples continuously so one rebuild distinguishes all three.
#
# Each sample records:
#   binfmt    the qemu-aarch64 entry's flags line (or ABSENT) — catches an F
#             flag that disappears partway through, which is H1's mechanism
#   cc1       total concurrent compiler processes  — low (1-2) means H2
#   cc1_emul  compilers running under qemu         — non-zero ANY sample means H1
#   qemu      all qemu-user processes              — high with cc1_emul=0 is H3
#   load      1-minute load average
#
# Usage (normally started by build.sh, not by hand):
#   sh scripts/binfmt-watchdog.sh --log out/build-diagnostics.log &
#
# Options:
#   --interval N   seconds between samples (default 20)
#   --log PATH     append samples here (default: stdout)
#   --parent PID   exit once this pid is gone (avoids orphaned loops)
#   --heal         also re-register the F flag when it goes missing.
#                  OFF BY DEFAULT — see the warning at heal_binfmt() below.
set -u

LOG_TAG="watchdog"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$script_dir/lib.sh"

BINFMT_ENTRY=/proc/sys/fs/binfmt_misc/qemu-aarch64
QEMU_STATIC=/usr/bin/qemu-aarch64-static

interval=20
logfile=""
parent_pid=""
heal=0

while [ $# -gt 0 ]; do
    case "$1" in
        --interval) interval="$2"; shift 2 ;;
        --log)      logfile="$2";  shift 2 ;;
        --parent)   parent_pid="$2"; shift 2 ;;
        --heal)     heal=1; shift ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# Append one line to the diagnostics log (or stdout when --log is absent).
emit() {
    if [ -n "$logfile" ]; then
        printf '%s\n' "$*" >> "$logfile"
    else
        printf '%s\n' "$*"
    fi
}

# Re-register the F-flagged binfmt entry. Only reached with --heal.
#
# WARNING — why this is off by default: fix-binfmt.sh unregisters the existing
# entry before registering the new one. Any foreign binary exec'd inside that
# window fails with ENOEXEC and takes the build down with it. Don't enable this
# until the log proves the flag is genuinely being wiped mid-build, and guard
# that unregister step first.
heal_binfmt() {
    # sudo -n (non-interactive) is mandatory: the sudo timestamp expires long
    # before a 2h build ends, and a password prompt on a backgrounded process
    # would hang the build instead of failing it.
    if [ ! -x "$QEMU_STATIC" ]; then
        emit "$(timestamp)  heal=SKIP reason=no-static-qemu"
        return 0
    fi
    if sudo -n sh "$script_dir/fix-binfmt.sh" >/dev/null 2>&1; then
        emit "$(timestamp)  heal=OK"
    else
        emit "$(timestamp)  heal=FAILED reason=sudo-or-register-error"
    fi
    return 0
}

timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Collect one sample. Must always succeed — a diagnostic must never be able to
# fail the build it is observing.
sample() {
    binfmt_state=ABSENT
    if [ -e "$BINFMT_ENTRY" ]; then
        # e.g. "flags: OCF" -> "OCF"; empty flags field is possible, hence the
        # fallback so the field is never blank in the log.
        binfmt_state=$(awk '/^flags:/ { print ($2 == "" ? "none" : $2) }' \
            "$BINFMT_ENTRY" 2>/dev/null || true)
        [ -n "$binfmt_state" ] || binfmt_state=unreadable
    fi

    # The [c]c1 / [q]emu bracket trick keeps grep's own argv from matching
    # itself in the ps output and inflating every count by one.
    procs=$(ps -eo args= 2>/dev/null || true)
    cc1_total=$(printf '%s\n' "$procs" | grep -c -- '[c]c1' || true)
    cc1_emul=$(printf '%s\n' "$procs" | grep -- '[c]c1' \
        | grep -c -- 'qemu-aarch64-static' || true)
    qemu_total=$(printf '%s\n' "$procs" | grep -c -- '[q]emu-aarch64-static' || true)

    loadavg=$(awk '{ print $1 }' /proc/loadavg 2>/dev/null || echo '?')

    emit "$(timestamp)  binfmt=$binfmt_state  cc1=$cc1_total  cc1_emul=$cc1_emul  qemu=$qemu_total  load=$loadavg"

    if [ "$heal" = "1" ] && ! binfmt_has_f "$BINFMT_ENTRY"; then
        heal_binfmt
    fi
    return 0
}

if [ -n "$logfile" ]; then
    mkdir -p "$(dirname -- "$logfile")" 2>/dev/null || true
    log "sampling every ${interval}s -> $logfile"
fi

emit "# --- watchdog start $(timestamp) (interval=${interval}s heal=${heal}) ---"
emit "# cc1_emul>0 = crossdirect NOT working (H1) | cc1 stuck at 1-2 = under-parallelized (H2)"
emit "# qemu high with cc1_emul=0 = emulated-glue tax (H3)"

while :; do
    # Stop once the build we were launched alongside is gone.
    if [ -n "$parent_pid" ] && ! kill -0 "$parent_pid" 2>/dev/null; then
        emit "# --- watchdog stop $(timestamp) (parent $parent_pid exited) ---"
        break
    fi
    sample
    sleep "$interval"
done
