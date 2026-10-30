#!/usr/bin/env bash
# Flash Ubuntu to a Xiaomi Mi 5 in fastboot mode (power + volume down).
#
#   scripts/flash.sh            flash boot + userdata (ERASES Android user data)
#   scripts/flash.sh --boot     only the boot image (kernel update / recovery)
#   scripts/flash.sh --try      boot once without flashing the boot partition
#                               (rootfs must already be on userdata)
#
# The bootloader must be unlocked (Mi Unlock tool). Android's system, vendor
# and modem partitions are not touched, so firmware stays available and you
# can go back by flashing a MIUI fastboot ROM.
set -euo pipefail
cd "${IMAGES_DIR:-$(dirname "$0")/../out}"

fastboot=${FASTBOOT:-fastboot}
command -v "$fastboot" >/dev/null || { echo "install fastboot (apt install fastboot / android-sdk-platform-tools)"; exit 1; }

# Release downloads ship the rootfs xz-compressed
if [ ! -f rootfs.sparse.img ] && [ -f rootfs.sparse.img.xz ] && [ "${1:-all}" = all ]; then
	echo "Decompressing rootfs.sparse.img.xz..."
	xz -dk rootfs.sparse.img.xz
fi

echo "Waiting for the phone in fastboot mode..."
product=$("$fastboot" getvar product 2>&1 | sed -n 's/^product: *//p' | head -n1)
if [ "$product" != "gemini" ]; then
	echo "Connected device reports product '$product', expected 'gemini' (Mi 5). Aborting."
	exit 1
fi
unlocked=$("$fastboot" getvar unlocked 2>&1 | sed -n 's/^unlocked: *//p' | head -n1)
[ "$unlocked" = "no" ] && { echo "Bootloader is locked - unlock it first (docs/INSTALL.md)."; exit 1; }

case "${1:-all}" in
--try)
	"$fastboot" boot boot.img
	;;
--boot)
	"$fastboot" flash boot boot.img
	"$fastboot" reboot
	;;
all)
	read -r -p "This ERASES the userdata partition (Android apps, photos, files). Type YES: " ok
	[ "$ok" = YES ] || exit 1
	"$fastboot" flash boot boot.img
	"$fastboot" flash userdata rootfs.sparse.img
	"$fastboot" reboot
	echo "Done. First boot takes ~1 minute (it grows the filesystem and copies firmware)."
	echo "Login: ubuntu / ubuntu (you will be asked to choose a new password)."
	;;
*)
	sed -n '2,12p' "$0"; exit 1 ;;
esac
