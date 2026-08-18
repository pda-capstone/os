PMBOOTSTRAP_VERSION = 3.11.1
INPUT_FILE = pmbootstrap_v$(PMBOOTSTRAP_VERSION)_input.generated

WORK_PATH = ${HOME}/.local/var/pmbootstrap
PMAPORTS_PATH := $(WORK_PATH)/cache_git/pmaports

CFG_FILE = ${HOME}/.config/pmbootstrap_v3.cfg

DEVICE := pda-tft
DEVICE_PATH := device/downstream/device-$(DEVICE)
DEVICE_PATH_LOCAL := pmaports/$(DEVICE_PATH)
DEVICE_PATH_GIT := $(PMAPORTS_PATH)/$(DEVICE_PATH)

KERNEL := rpi
KERNEL_PATH := device/downstream/linux-$(KERNEL)
KERNEL_PATH_LOCAL := pmaports/$(KERNEL_PATH)
KERNEL_PATH_GIT := $(PMAPORTS_PATH)/$(KERNEL_PATH)

DEMO_APP_PATH := main/pda-demo-app
DEMO_APP_PATH_LOCAL := pmaports/$(DEMO_APP_PATH)
DEMO_APP_PATH_GIT := $(PMAPORTS_PATH)/$(DEMO_APP_PATH)

DAEMON_PATH := main/pda-hotswapd
DAEMON_PATH_LOCAL := pmaports/$(DAEMON_PATH)
DAEMON_PATH_GIT := $(PMAPORTS_PATH)/$(DAEMON_PATH)

BACKGROUNDS_PATH := main/pda-backgrounds
BACKGROUNDS_PATH_LOCAL := pmaports/$(BACKGROUNDS_PATH)
BACKGROUNDS_PATH_GIT := $(PMAPORTS_PATH)/$(BACKGROUNDS_PATH)

# Configuration
BOOT_SIZE = 2048
EXTRA_PACKAGES = vim,git,pda-demo-app,pda-hotswapd,pda-hotswapd-doc,mandoc,pda-backgrounds
USER_INTERFACE = phosh

PMAPORTS_URL = https://gitlab.postmarketos.org/postmarketOS/pmaports.git
PMAPORTS_COMMIT = b2ec188d30f6408585d44e7f6473142e4c052a18

OUTPUT_DIR = output

.PHONY: all vars config init copy kernel install image clean

all: vars copy
	@echo '[DONE WITH ALL]'

# echo our variables to easily verify.
vars:
	@echo
	@echo
	@echo '[Variables]'
	@echo 'WORK_PATH' $(WORK_PATH)
	@echo 'PMAPORTS_PATH' $(PMAPORTS_PATH)
	@echo
	@echo 'DEVICE' $(DEVICE)
	@echo 'DEVICE_PATH' $(DEVICE_PATH)
	@echo 'DEVICE_PATH_LOCAL' $(DEVICE_PATH_LOCAL)
	@echo 'DEVICE_PATH_GIT' $(DEVICE_PATH_GIT)
	@echo
	@echo 'EXTRA_PACKAGES' $(EXTRA_PACKAGES)
	@echo '[DONE WITH VARS]'

# We automate calling `pmbootstrap init`, giving us a single command setup with
# no interaction required.
init: config
	pmbootstrap init --shallow-initial-clone < $(INPUT_FILE)
	pmbootstrap config auto_zap_misconfigured_chroots yes
	pmbootstrap config device $(DEVICE)
	# pmbootstrap config timezone 'America/Los_Angeles'
	@echo '[DONE WITH INIT]'

# We create a file that can be used as inputs to the interactive
# `pmbootstrap init`. This will be highly dependent on the interactive
# interface of `pmbootstrap init`, so we want to make sure versions match.
# Consider running `make config` then checking the contents of the file whilst
# manually running `pmbootstrap init` to see if the inputs are the same. This
# configuration is just for initialization, not what will be installed. We can
# change it later.
config:
ifneq ($(PMBOOTSTRAP_VERSION), $(shell pmbootstrap --version))
	$(error pmbootstrap version must match configuration version $(PMBOOTSTRAP_VERSION))
endif
	rm -f $(INPUT_FILE)
	touch $(INPUT_FILE)
	echo $(WORK_PATH) >> $(INPUT_FILE)
	echo $(PMAPORTS_PATH) >> $(INPUT_FILE)
	echo edge >> $(INPUT_FILE)
	echo raspberry >> $(INPUT_FILE)
	echo pi5 >> $(INPUT_FILE)
	echo y >> $(INPUT_FILE)
	echo user >> $(INPUT_FILE)
	echo pulseaudio >> $(INPUT_FILE)
	echo wpa_supplicant >> $(INPUT_FILE)
	echo developer >> $(INPUT_FILE)
	echo $(USER_INTERFACE) >> $(INPUT_FILE)
	echo systemd >> $(INPUT_FILE)
	echo y >> $(INPUT_FILE)
	echo 0 >> $(INPUT_FILE)
	echo $(BOOT_SIZE) >> $(INPUT_FILE)
	echo '' >> $(INPUT_FILE)
	echo '' >> $(INPUT_FILE)
	echo n >> $(INPUT_FILE)
	echo n >> $(INPUT_FILE)
	echo $(EXTRA_PACKAGES) >> $(INPUT_FILE)
	echo '' >> $(INPUT_FILE)
	echo $(DEVICE) >> $(INPUT_FILE)
	echo y >> $(INPUT_FILE)
	echo y >> $(INPUT_FILE)
	echo '' >> $(INPUT_FILE)
	echo '' >> $(INPUT_FILE)

# Our custom files are copied into the pmaports git cache to allow
# pmbootstrap to see them.
copy: init
	@echo
	@echo
	@echo '[Copying Packages]'
	rm -rf $(DEVICE_PATH_GIT)
	cp -r $(DEVICE_PATH_LOCAL) $(DEVICE_PATH_GIT)
	@echo
	rm -rf $(DEMO_APP_PATH_GIT)
	cp -r $(DEMO_APP_PATH_LOCAL) $(DEMO_APP_PATH_GIT)
	@echo
	rm -rf $(DAEMON_PATH_GIT)
	cp -r $(DAEMON_PATH_LOCAL) $(DAEMON_PATH_GIT)
	@echo
	rm -rf $(BACKGROUNDS_PATH_GIT)
	cp -r $(BACKGROUNDS_PATH_LOCAL) $(BACKGROUNDS_PATH_GIT)
	@echo
	rm -rf $(KERNEL_PATH_GIT)
	cp -r $(KERNEL_PATH_LOCAL) $(KERNEL_PATH_GIT)
	@echo '[DONE WITH COPY]'

# Command to rebuild kernel with the 
kernel: copy
	@echo
	@echo
	@echo '[APPLYING FRAGMENT AND REBUILDING KERNEL]'
	sh scripts/apply-fragment.sh $(KERNEL_PATH_GIT)/common-changes.config \
		config/disabled-subsystems.fragment
	@echo
	@echo '[ADDING HASH]'
	sum=$$(sha512sum $(KERNEL_PATH_GIT)/common-changes.config | cut -d' ' -f1); \
	awk -v s="$$sum" '/  common-changes\.config$$/ { print s "  common-changes.config"; next } { print }' \
		$(KERNEL_PATH_GIT)/APKBUILD > $(KERNEL_PATH_GIT)/APKBUILD.tmp; \
	mv $(KERNEL_PATH_GIT)/APKBUILD.tmp $(KERNEL_PATH_GIT)/APKBUILD
	@echo
	@echo '[COMPILING KERNEL]'
	pmbootstrap build --force linux-$(KERNEL)

install:
ifndef SDCARD
	$(error SDCARD must be set)
endif
	pmbootstrap install --sdcard=$(SDCARD)
	@echo '[DONE WITH INSTALL]'

image:
	mkdir $(OUTPUT_DIR)
	pmbootstrap install
	pmbootstrap export $(OUTPUT_DIR)
	@echo '[DONE WITH IMAGE CREATION]'

clean:
	-pmbootstrap zap --all
	-sudo rm -rf $(WORK_PATH)
	-rm -f $(CFG_FILE)
	@echo '[CLEAN DONE]'
