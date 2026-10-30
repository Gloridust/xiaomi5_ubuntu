#!/usr/bin/env bash
# Build everything: kernel -> Ubuntu 26.04 rootfs -> boot.img + rootfs image.
#
#   sudo ./build.sh                 console UI with buffyboard keyboard
#   sudo UI=sway ./build.sh         + touch GUI (sway, terminal, wvkbd)
#   sudo UI=phosh ./build.sh        + phone shell (phosh, squeekboard)
#   sudo WIFI_SSID=home WIFI_PASSWORD=secret ./build.sh
#
# Then put the phone in fastboot mode and run scripts/flash.sh
set -euo pipefail
cd "$(dirname "$0")"

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0"; exit 1; }

scripts/00-host-deps.sh
scripts/10-build-kernel.sh
scripts/20-build-rootfs.sh
scripts/30-make-images.sh

echo
echo "Build finished. Next: boot the phone into fastboot (power + volume down),"
echo "connect USB and run:  scripts/flash.sh"
