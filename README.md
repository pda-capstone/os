# Pocket Distro Alpha OS

This repository contains tools and configuration to install PostmarketOS plus
Pocket Distro Alpha software and configuration onto a Raspberry Pi 5 based
smartphone-like device.

A two command install can put the operating system on an SD card. The default
install includes the PDA demo app and hotswap daemon. A dsi display is also
enabled.

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

3. Insert Micro SD card and identify it. It will probably be sdb.

```bash
lsblk
```

4. Install onto the card. Replace X with the letter identified by `lsblk`

```bash
make SDCARD=/dev/sdX install
```

# Post Install

* Connect to wifi from the quick settings pulldown menu.
* Update the system with `sudo apk update` then `sudo apk upgrade`.
* After connecting to wifi, you can use SSH with `ssh user@pda-tft`.
* The hotspot on the device can be turned on and connected to, allowing the
  use of SSH without needing to connect the device to a wifi network.

> [!IMPORTANT]
> You may want to change the sshd config for security purposes. For example,
> disabling keyboard authentification.

* Use the quick settings menu to switch between portrait and landscape mode
  (hopefully we can get sensors in the future).
* Use the quick settings menu to switch between docked and undocked mode.

# Troubleshooting

* Run `make clean` then `make` to delete existing files and reinitialize
* Consult the PostmarketOS wiki: https://wiki.postmarketos.org/wiki/Pmbootstrap

# How This Works

`pmbootstrap` is a command line tool to help install PostmarketOS on a wide
variety of devices. `pmbootstrap` manages configuration of the image we
install on the device then builds and installs it, including dealing with
cross compiling, additional packages, and more to get a usable system.

`pmbootstrap` relies on the pmaports package repository, containing device
specific configuration, to know what to install on the device. This repository
is cloned onto the computer running `pmbootstrap`. We copy our own custom build
files into this local repository that allows us to use custom configuration for
our own hardware and software for our specific device.

We create a custom device package for our hardware, in the format of APKBUILD,
and we tell `pmbootstrap` to use this package, which contains information to
get the hardware working, such as the display, and to install our custom
software. Our software, such as the demo app, are also packaged here in
APKBUILD format and retrieve source code from GitHub releases

A `makefile` wraps all of these commands and handles setup, giving us a two
command setup and install onto an SD card.

# Maintenance

## Dependencies

pmaports and pmbootstrap should both be updated to remain compatible.
pmbootstrap can be updated with `nix flake update`.
Use `make` to update the pmaports cache locally, no need to
change anything else in this repo because the most recent will be cloned on
setup. We could pin to a commit, but that probably isn't necessary.

If new custom packages are added, the Makefile should be updated.
If the existing releases for packages are updated, like a new GitHub release of
the demo app, then the checksum in the APKBUILD file would need to be updated
(don't forget to use `make copy` to update pmaports).

## New Hardware

When new hardware support is needed, a new device package will need to be
created, or an existing package must be updated. The usercfg.txt may need to be
changed to allow new hardware to work.

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
