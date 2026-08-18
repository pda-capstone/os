# ARM MacBook Build Test Results

**Tested by:** Camellia Tran  
**Date:** August 17, 2026  
**Machine:** ARM MacBook (Apple Silicon)  
**VM:** UTM with Ubuntu 24.04.3 ARM64  
**Branch:** tanner/setup-script  

## Summary

Build completed successfully — `[DONE WITH ALL]` confirmed at end of output.

## Setup Steps Required

The following steps were needed to get the build working on a fresh ARM Mac:

1. Install UTM from utm.app
2. Create a Linux VM using Ubuntu 24.04.3 ARM64 ISO
3. Install pmbootstrap manually — it is not included in the setup script:
```bash
pip3 install git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git --break-system-packages
export PATH=$PATH:/home/$USER/.local/bin
```
4. Clone the repo and switch to the branch:
```bash
git clone https://github.com/pda-capstone/os.git
cd os
git checkout tanner/setup-script
```
5. Run the build:
```bash
make
```

## Issues Found

### Issue 1 — pmbootstrap not installed by default
The Makefile requires pmbootstrap 3.11.1 but it is not installed automatically.
The setup script has no step to install it.

**Fix needed:** Add pmbootstrap installation to the Makefile or README setup instructions.

### Issue 2 — PATH not set after pmbootstrap installation
After installing pmbootstrap the command is not found until PATH is updated manually.

**Fix needed:** Add the following to the setup script or Makefile:
```bash
export PATH=$PATH:/home/$USER/.local/bin
```

### Issue 3 — downstream path bug still present
The Makefile copies device packages to `device/downstream/` which no longer exists in the current PostmarketOS pmaports tree. The correct path is `device/testing/`.



**Fix needed:** Change all references from `device/downstream/` to `device/testing/` in the Makefile.

## What Was Not Tested

- SD card flashing — no microSD card or card reader available during this test
- Will borrow a card from Tanner or EPL lab to complete this step


The build process works on an ARM MacBook using UTM with Ubuntu ARM64.
Three documentation and script fixes are needed before this is fully reproducible
on a fresh machine without prior knowledge of the setup process.
