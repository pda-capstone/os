WORK_PATH := ${HOME}/.local/var/pmbootstrap
PMAPORTS_PATH := $(WORK_PATH)/cache_git/pmaports

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

CFG_DIR := ${HOME}/.config
CFG_FILE := $(CFG_DIR)/pmbootstrap_v3.cfg
VERSION_FILE := $(WORK_PATH)/version

EXTRA_PACKAGES := vim,pda-demo-app
# EXTRA_PACKAGES := vim,pda-demo-app,pda-hotswapd

PMAPORTS_URL := https://gitlab.postmarketos.org/postmarketOS/pmaports.git

.PHONY: all vars setup copy clean

all: vars setup copy
	@echo '[DONE WITH ALL]'

# echo our variables to verify.
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
	@echo 'KERNEL_PATH' $(KERNEL_PATH)
	@echo 'KERNEL_PATH_LOCAL' $(KERNEL_PATH_LOCAL)
	@echo 'KERNEL_PATH_GIT' $(KERNEL_PATH_GIT)
	@echo
	@echo 'DEMO_APP_PATH' $(DEMO_APP_PATH)
	@echo 'DEMO_APP_PATH_LOCAL' $(DEMO_APP_PATH_LOCAL)
	@echo 'DEMO_APP_PATH_GIT' $(DEMO_APP_PATH_GIT)
	@echo
	@echo 'DAEMON_PATH' $(DAEMON_PATH)
	@echo 'DAEMON_PATH_LOCAL' $(DAEMON_PATH_LOCAL)
	@echo 'DAEMON_PATH_GIT' $(DAEMON_PATH_GIT)
	@echo
	@echo 'CFG_DIR' $(CFG_DIR)
	@echo 'CFG_FILE' $(CFG_FILE)
	@echo 'VERSION_FILE' $(VERSION_FILE)
	@echo
	@echo 'EXTRA_PACKAGES' $(EXTRA_PACKAGES)
	@echo
	@echo 'PMAPORTS_URL' $(PMAPORTS_URL)
	@echo '[DONE WITH VARS]'

# Set up pmbootstrap files and configuration for our device.
# This is an alternative to `pmbootstrap init --shallow-initial-clone` that
# would require a lot of manual interaction just to init, which we override
# anyways.
setup:
	@echo
	@echo
	@echo '[Creating Config File]'
	mkdir -p $(CFG_DIR)
	rm -f $(CFG_FILE)
	touch $(CFG_FILE)
	echo '[pmbootstrap]' >> $(CFG_FILE)
	echo 'aports = $(PMAPORTS_PATH)' >> $(CFG_FILE)
	echo 'boot_size = 2048' >> $(CFG_FILE)
	echo 'device = pda-tft' >> $(CFG_FILE)
	echo 'extra_packages = $(EXTRA_PACKAGES)' >> $(CFG_FILE)
	echo 'hostname = pda-tft' >> $(CFG_FILE)
	echo 'is_default_channel = False' >> $(CFG_FILE)
	echo 'systemd = always' >> $(CFG_FILE)
	echo 'ui = phosh' >> $(CFG_FILE)
	echo 'work = $(WORK_PATH)' >> $(CFG_FILE)
	echo '' >> $(CFG_FILE)
	echo '[providers]' >> $(CFG_FILE)
	echo '' >> $(CFG_FILE)
	echo '[mirrors]' >> $(CFG_FILE)
	echo '' >> $(CFG_FILE)
	@echo
	@echo
	@echo '[Creating Version File]'
	mkdir -p $(WORK_PATH)
	rm -f $(VERSION_FILE)
	touch $(VERSION_FILE)
	echo '8' > $(VERSION_FILE)
	@echo
	@echo
	@echo '[Creating Pmaports Cache]'
	rm -rf $(PMAPORTS_PATH)
	mkdir -p $(WORK_PATH)/cache_git
	git clone $(PMAPORTS_URL) $(PMAPORTS_PATH) --depth=1
	@echo
	@echo
	@echo '[Setting Config]'
	pmbootstrap config aports $(PMAPORTS_PATH)
	pmbootstrap config auto_zap_misconfigured_chroots no
	pmbootstrap config boot_size 2048
	pmbootstrap config build_default_device_arch False
	pmbootstrap config build_pkgs_on_install True
	pmbootstrap config ccache_size 5G
	pmbootstrap config device $(DEVICE)
	pmbootstrap config extra_packages $(EXTRA_PACKAGES)
	pmbootstrap config extra_space 0
	pmbootstrap config hostname $(DEVICE)
	pmbootstrap config is_default_channel False
	pmbootstrap config kernel stable
	pmbootstrap config locale en_US.UTF-8
	pmbootstrap config qemu_redir_stdio False
	pmbootstrap config ssh_key_glob ~/.ssh/*.pub
	pmbootstrap config ssh_keys True
	pmbootstrap config sudo_timer False
	pmbootstrap config systemd always
	pmbootstrap config timezone PDT
	pmbootstrap config ui phosh
	pmbootstrap config ui_extras False
	pmbootstrap config user user
	pmbootstrap config work $(WORK_PATH)
	@echo '[DONE WITH SETUP]'

# Our custom files are copied into the pmaports git cache to allow
# pmbootstrap to see them.
copy:
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
	rm -rf $(KERNEL_PATH_GIT)
	cp -r $(KERNEL_PATH_LOCAL) $(KERNEL_PATH_GIT)
	@echo '[DONE WITH COPY]'

clean:
	-pmbootstrap zap
	-sudo rm -rf $(WORK_PATH)
	-rm -f $(CFG_FILE)
