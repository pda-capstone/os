WORK_PATH := ${HOME}/.local/var/pmbootstrap
PMAPORTS_PATH := $(WORK_PATH)/cache_git/pmaports
DEVICE := pda-tft
DEVICE_PATH := device/downstream/device-$(DEVICE)
DEVICE_PATH_LOCAL := pmaports/$(DEVICE_PATH)
DEVICE_PATH_GIT := $(PMAPORTS_PATH)/$(DEVICE_PATH)

.PHONY: setup clean

setup:
	@echo 'WORK_PATH' $(WORK_PATH)
	@echo 'PMAPORTS_PATH' $(PMAPORTS_PATH)
	@echo 'DEVICE' $(DEVICE)
	@echo 'DEVICE_PATH' $(DEVICE_PATH)
	@echo 'DEVICE_PATH_LOCAL' $(DEVICE_PATH_LOCAL)
	@echo 'DEVICE_PATH_GIT' $(DEVICE_PATH_GIT)
	@echo
	@echo
	pmbootstrap init --shallow-initial-clone
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
	pmbootstrap config extra_packages vim
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
	@echo
	echo '[Copying Packages]'
	rm -rf $(DEVICE_PATH_GIT)
	cp -r $(DEVICE_PATH_LOCAL) $(DEVICE_PATH_GIT)

clean:
	-pmbootstrap zap
	-sudo rm -rf ~/.local/var/pmbootstrap
	-rm -f ~/.config/pmbootstrap_v3.cfg
