#!/bin/sh
# Fix crossdirect falling back to QEMU emulation.
#
# Symptom: cold builds take hours; `top` shows `{cc1} /usr/bin/qemu-aarch64-static`
# (the target compiler running EMULATED) instead of a native cross-compiler.
#
# Root cause: the aarch64 binfmt_misc handler is registered WITHOUT the `F`
# (fix-binary) flag. Without `F`, QEMU is not preloaded into the kernel, so
# crossdirect can't exec its native wrapper from inside the emulated chroot and
# silently degrades to full emulation.
#
# This script removes the bad registration and re-registers qemu-aarch64 WITH
# the `F` flag (flags: OCF), reusing the exact ELF/aarch64 magic + mask.
#
# pmbootstrap only registers qemu-aarch64 when it's missing, so once this good
# entry exists, pmbootstrap leaves it alone.
#
# Run as root:  doas sh scripts/fix-binfmt.sh
set -eu

BINFMT=/proc/sys/fs/binfmt_misc
ENTRY="$BINFMT/qemu-aarch64"
INTERP=/usr/bin/qemu-aarch64-static

if [ "$(id -u)" != "0" ]; then
	echo "ERROR: must run as root, e.g.  doas sh scripts/fix-binfmt.sh" >&2
	exit 1
fi

if [ ! -d "$BINFMT" ]; then
	echo "ERROR: binfmt_misc is not mounted at $BINFMT" >&2
	echo "Try:  doas mount -t binfmt_misc none $BINFMT" >&2
	exit 1
fi

# The `F` flag pins the interpreter at registration time, so it must exist now.
if [ ! -x "$INTERP" ]; then
	echo "ERROR: interpreter $INTERP not found (or not executable)." >&2
	echo "Locate the static qemu-aarch64 and edit INTERP in this script." >&2
	exit 1
fi

# Remove any existing registration (a plain root redirect; `tee` fails with EIO
# on these control files because it opens them O_TRUNC).
if [ -e "$ENTRY" ]; then
	echo "Removing existing qemu-aarch64 registration..."
	echo -1 > "$ENTRY"
fi

echo "Registering qemu-aarch64 with the F flag..."
# printf converts the \xNN escapes (including null bytes) into the raw magic/mask
# bytes before they reach the kernel -- works on every kernel version.
printf ':qemu-aarch64:M:0:\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:%s:OCF\n' "$INTERP" > "$BINFMT/register"

echo
echo "Result:"
cat "$ENTRY"
echo
if grep -q '^flags:.*F' "$ENTRY"; then
	echo "OK: F flag present -> crossdirect can now use the native cross-compiler."
	echo "Next: start a build and check 'top' -- cc1 should have NO qemu prefix."
else
	echo "WARNING: F flag still missing. Something re-registered without F." >&2
	exit 1
fi
