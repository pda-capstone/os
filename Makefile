# Native-Linux convenience wrapper. pmbootstrap runs directly on the host (no
# Docker), so these targets just call the scripts.
#
# Usage:
#   make setup          # one-time: install pmbootstrap + host tools
#   make build          # produce the hardened postmarketOS image -> out/
#   make verify         # verify the disabled subsystems are actually off
#   make all            # build + verify
#   make flash SDCARD=/dev/sdX   # write the image straight to an SD card / CM5
#   make clean          # remove the exported image (out/)
#   make clean-cache    # zap pmbootstrap chroots (forces a cold rebuild)

include config/build.env
export

.PHONY: setup build verify all flash clean clean-cache

setup:
	sh scripts/setup.sh

build:
	sh scripts/build.sh

verify:
	sh scripts/verify-disabled.sh

all: build verify

# Flash directly to hardware. SDCARD must point at the target block device.
# This re-runs install writing to the card; the hardened kernel is already built.
flash:
	@test -n "$(SDCARD)" || { echo "Usage: make flash SDCARD=/dev/sdX"; exit 1; }
	pmbootstrap --details-to-stdout install --sdcard=$(SDCARD)

clean:
	rm -rf "$(OUTPUT_DIR)"

clean-cache: clean
	-pmbootstrap zap -y
