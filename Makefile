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

.PHONY: setup vars init config copy clean

setup: vars init config copy
	@echo '[DONE WITH SETUP]'

# echo our variables to verify.
vars:
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
	@echo '[DONE]'

# Set up pmbootstrap.
init:
	@echo '[Initing pmbootstrap]'
	pmbootstrap init --shallow-initial-clone
	@echo '[DONE]'

# We set the config to fit our hardware.
config:
	@echo '[Setting Config]'
	pmbootstrap config aports $(PMAPORTS_PATH)
	pmbootstrap config auto_zap_misconfigured_chroots no
	pmbootstrap config boot_size 2048
	pmbootstrap config build_default_device_arch False
	pmbootstrap config build_pkgs_on_install True
	pmbootstrap config ccache_size 5G
	pmbootstrap config device $(DEVICE)
	pmbootstrap config extra_packages vim,pda-demo-app
	# pmbootstrap config extra_packages vim,pda-demo-app,pda-hotswapd
	pmbootstrap config extra_space 0
	pmbootstrap config hostname $(DEVICE)
	pmbootstrap config is_default_channel False
	pmbootstrap config jobs 4
	pmbootstrap config kernel stable
	pmbootstrap config locale en_US.UTF-8
	pmbootstrap config qemu_redir_stdio False
	pmbootstrap config ssh_key_glob ~/.ssh/*.pub
	pmbootstrap config ssh_keys True
	pmbootstrap config sudo_timer False
	pmbootstrap config systemd always
	pmbootstrap config timezone GMT
	pmbootstrap config ui phosh
	pmbootstrap config ui_extras False
	pmbootstrap config user user
	pmbootstrap config work $(WORK_PATH)
	@echo '[DONE]'

# Our custom files are copied into the pmaports git cache to allow
# pmbootstrap to see them.
copy:
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
	@echo '[DONE]'

clean:
	-pmbootstrap zap
	-sudo rm -rf ~/.local/var/pmbootstrap
	-rm -f ~/.config/pmbootstrap_v3.cfg
