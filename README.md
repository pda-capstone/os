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

When asked to configure pmbootstrap, select defaults for the cache directories
(Just hit enter).
Select `edge` for the branch.
Select `raspberry` for vendor and `pi5` for device.
Select `y` when given the downstream warning.
Otherwise, just hit enter to use defaults.

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
