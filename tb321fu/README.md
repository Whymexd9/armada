# Armada port: Lenovo Legion Y700 (TB321FU)

This directory contains the first-stage Armada device port for the Lenovo Legion Y700 / TB321FU (Snapdragon 8 Gen 3 / SM8650).

The port deliberately reuses the already verified boot/kernel/device payload from `GUF296/ubuntu-y700-build-ci` while keeping Armada's Fedora bootc userspace, Steam/FEX/Proton stack, Gamescope and KDE components.

## Current stage

Implemented in this branch:

- dedicated `tb321fu` port configuration;
- verified SHA256-pinned Y700 kernel and device payload inputs;
- replacement of Armada's generic kernel with `7.1.1-g5df8e852ea72`;
- installation of `sm8650-lenovo-tb321fu.dtb`;
- extraction of Y700 kernel modules from the verified device deb archive;
- import of firmware, udev rules, systemd units and ALSA data without copying the Ubuntu userspace wholesale;
- verification of the firmware files required by the Adreno 830 / SM8650 stack;
- normal Armada dracut/initramfs generation remains after the device kernel installation.

## Verified reference inputs

The current bootstrap inputs are the same ones used by the working Y700 Ubuntu build:

- `y700-kernel-artifacts-7.1.1-g5df8e852ea72.tar.gz`
- `y700-device-debs-20260624-201420-compat1.tar.gz`
- `y700-verified-grub-template-userdata-20260624-201420.img`
- DTB: `sm8650-lenovo-tb321fu.dtb`

Exact URLs and checksums live in `port.env`.

## Not complete yet

A successful container build is only the first milestone. The final flashable TB321FU image still needs a Y700-specific boot path that reconciles Armada/bootc's OSTree boot model with the tablet's verified QCOMRAMP/GRUB flow. Sensor, haptics and camera packages also need Fedora-native integration rather than blindly installing Ubuntu packages.

Do not flash an image from this branch until the boot-image stage is explicitly marked validated.
