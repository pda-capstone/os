#!/usr/bin/env bash

echo '[Setting config]'

DEVICE=pda-hackberry

echo "[Device: $DEVICE]"

pmbootstrap config aports $HOME/.local/var/pmbootstrap/cache_git/pmaports
pmbootstrap config auto_zap_misconfigured_chroots no
pmbootstrap config boot_size 2048
pmbootstrap config build_default_device_arch False
pmbootstrap config build_pkgs_on_install True
pmbootstrap config ccache_size 5G
pmbootstrap config device $DEVICE
pmbootstrap config extra_packages vim
pmbootstrap config extra_space 0
pmbootstrap config hostname $DEVICE
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
pmbootstrap config work $HOME/.local/var/pmbootstrap

echo '[CONFIG DONE]'

mkdir -p $HOME/.local/var/pmbootstrap/cache_git/pmaports/device/testing
cp -r ./pmaports/device/testing/device-pda-hackberry $HOME/.local/var/pmbootstrap/cache_git/pmaports/device/testing/device-pda-hackberry
