# os

Power-optimized PostmarketOS image for the CM5 handheld, kernel config, build pipeline, and suspend/resume

# Prerequisites

* Micro SD card
* Linux (A virtual machine with SD card access works)
* Nix with flakes

The recommended way is to start a linux virtual machine that can read and
write to the Micro SD card.

## Windows

TODO

## MacOS

TODO

## Linux

Nix can be installed on top of any linux distro.
https://nixos.org/download/#nix-install-linux

# Usage

1. Clone this git repo

```bash
git clone https://github.com/pda-capstone/os.git
cd os
```

2. Perform setup and configuration

```bash
nix develop
make clean
make
pmbootstrap init # Use to configure beyond the default
```

3. Insert Micro SD card and identify it

```bash
lsblk
```

4. Install

replace X with the number identified by `lsblk`

```bash
pmbootstrap install --sdcard=/dev/sdX
```

# Troubleshooting

* Run `make clean` then `make` to delete existing files and reinitialize
* Consult the PostmarketOS wiki: https://wiki.postmarketos.org/wiki/Pmbootstrap

# Maintenance

pmaports and pmbootstrap should both be updated to remain compatible.
pmbootstrap can be updated with `nix flake update`.
Use `make clean` then `make` to update the pmaports cache locally, no need to
change anything else in this repo because the most recent will be cloned on
setup.

If new custom packages are added, the Makefile should be updated.

# Useful Links

https://wiki.postmarketos.org/wiki/Porting_to_a_new_device
https://wiki.postmarketos.org/wiki/Phosh
https://wiki.postmarketos.org/wiki/USB_Network
https://wiki.postmarketos.org/wiki/USB_Internet
https://docs.postmarketos.org/pmbootstrap/main/cross_compiling.html

https://wiki.alpinelinux.org/wiki/Creating_an_Alpine_package
https://wiki.alpinelinux.org/wiki/APKBUILD_examples
https://wiki.alpinelinux.org/wiki/Repositories

https://wiki.alpinelinux.org/wiki/Raspberry_Pi
https://trac.gateworks.com/wiki/linux/OTG#USBDeviceMode
https://pip-assets.raspberrypi.com/categories/685-app-notes-guides-whitepapers/documents/RP-009276-WP-1-Using%20OTG%20mode%20on%20Raspberry%20Pi%20SBCs.pdf
https://github.com/macmpi/xg_multi
