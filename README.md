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
make clean # This will fail on first time setup
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
