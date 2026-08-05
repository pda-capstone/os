# hardened-pmos-build (native Linux)

Reproducible build of a **custom postmarketOS image for the Raspberry Pi CM5**
(BCM2712, aarch64) whose kernel has selected subsystems **disabled** — the
native-Linux variant that runs `pmbootstrap` directly (no Docker).

> This is the Linux twin of the Windows/Docker project. The config, kernel
> recipe, and validation are identical; the difference is that here pmbootstrap
> runs on the host, crossdirect is enabled (fast builds), and you can flash the
> CM5 directly. Use this on a Linux machine; use the Docker variant on Windows.

## How it works

- The disabled subsystems are declared in
  [`config/disabled-subsystems.fragment`](config/disabled-subsystems.fragment).
- The CM5 kernel is Alpine's **`linux-rpi`**; we vendor its recipe in
  [`kernel/linux-rpi/`](kernel/linux-rpi/), inject our disables, and **compile
  the kernel from source** so postmarketOS installs our hardened kernel.
- [`scripts/build.sh`](scripts/build.sh) drives pmbootstrap end to end.
- CI ([`.github/workflows/build.yml`](.github/workflows/build.yml)) does the same
  on a Linux runner whenever `config/` or `kernel/` changes.

## Prerequisites

- A Linux host (bare metal, dual-boot, or a full VM). x86 is fine — the kernel
  is cross-compiled. **Debian/Ubuntu is the supported, tested host**: `setup.sh`
  installs `qemu-user-static`, which registers the aarch64 QEMU binfmt with the
  **`F` (fix-binary) flag** that crossdirect needs for fast, native-speed builds.
  Other distros (Alpine, etc.) may register the binfmt *without* `F`, in which
  case builds silently fall back to slow full emulation — see "Fast builds"
  below.
- `sudo` privileges (pmbootstrap uses sudo for chroots; it refuses to run as root).
- `~/.local/bin` on your `PATH`.

## Setup (once)

**Fresh VM, one command.** On a bare Debian/Ubuntu box this installs git, clones
the repo to `~/pmos-hardened-linux`, runs setup, and confirms the crossdirect
fast path (self-healing the `F` flag if needed):

```sh
curl -fsSL https://raw.githubusercontent.com/quinnwillett/pmos-hardened-linux/main/scripts/bootstrap-vm.sh | sh
```

It's idempotent — safe to re-run. Add `--build` to go straight into the first
build (clone first so the flag reaches the script):

```sh
git clone https://github.com/quinnwillett/pmos-hardened-linux.git
sh pmos-hardened-linux/scripts/bootstrap-vm.sh --build
```

**Or do it by hand** from an existing checkout:

```sh
make setup          # installs pmbootstrap + host tools (git, kpartx, qemu-user-static, ...)
pmbootstrap --version   # sanity check -> 3.10.3
```

If `pmbootstrap` isn't found afterward, add `~/.local/bin` to your PATH:
```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile && . ~/.profile
```

## Fast builds (crossdirect)

Cross-compiling for aarch64 on an x86 host is fast **only** when the QEMU binfmt
is registered with the `F` flag; otherwise the compiler runs fully emulated and a
cold kernel build takes hours instead of ~20 minutes. On Debian/Ubuntu `setup.sh`
handles this. Verify before your first build:

```sh
cat /proc/sys/fs/binfmt_misc/qemu-aarch64      # want: flags: ...F...
```

`build.sh` also **checks this automatically** and fails fast (rather than
emulating for hours) if the `F` flag is missing. If it ever is, re-register it:

```sh
sudo sh scripts/fix-binfmt.sh
```

While a build runs, you can confirm it's going native: `top` should show
`cc1`/`cc1plus` with **no** `qemu-aarch64-static` prefix.

## Build

```sh
make build          # compile the hardened kernel + build the image -> out/
make verify         # confirm the subsystems are actually off in the compiled kernel
make all            # build + verify
```

`DEVICE=raspberry-pi5` in [`config/build.env`](config/build.env) is already
correct for the CM5. The first build compiles the kernel (with crossdirect,
~tens of minutes); later builds reuse the ccache and are faster.

## Flash to the CM5

Once built, write it straight to the card / eMMC:
```sh
make flash SDCARD=/dev/sdX      # replace sdX with the REAL device (check with lsblk!)
```
Double-check the device name — writing to the wrong one destroys data.

## Editing what gets disabled

Add lines to [`config/disabled-subsystems.fragment`](config/disabled-subsystems.fragment):
```
# CONFIG_BT is not set
# CONFIG_WIRELESS is not set
```
`apply-fragment.sh` turns these into `CONFIG_X=n` in the recipe, the kernel is
recompiled, and `verify-disabled.sh` confirms they're off in the compiled config.

## Security note on kernel sources

The recipe fetches the kernel source from Alpine's official distfiles, and the
`sha512sums` are Alpine's own known-good hashes (only our edited
`common-changes.config` is re-hashed at build time). So every download is
verified against a trusted hash — a tampered mirror fails the check and the build
aborts. See [`kernel/linux-rpi/APKBUILD`](kernel/linux-rpi/APKBUILD).

## Reproducibility

Pin everything in [`config/build.env`](config/build.env)
(`PMBOOTSTRAP_VERSION`, `KERNEL_PKG`) and the vendored recipe version, plus
`SOURCE_DATE_EPOCH` from the repo's HEAD commit. Set `PMAPORTS_REF` to a real
commit for full determinism (it's empty by default and the build warns).

## Deferred: boot test

`scripts/boot-test.sh` is a stub. On Linux you can also boot-test locally by
flashing a spare card and powering the CM5, or wire it into CI on a self-hosted
CM5 runner later.
