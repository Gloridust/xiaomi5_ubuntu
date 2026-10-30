#!/usr/bin/env bash
# Copy the Mi 5's signed firmware off the phone into ./firmware/, so it is
# baked into the image at build time. (Optional: the phone also does this by
# itself on first boot.)
#
# Works with the phone in TWRP recovery, or booted into a rooted Android,
# connected by USB with adb enabled.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_cmd adb

dest="${FIRMWARE_DIR}/raw"
mkdir -p "$dest"
adb wait-for-device

pull_dir() {  # pull a directory from the phone if it exists
	if adb shell "[ -d '$1' ]" 2>/dev/null; then
		log "Pulling $1"
		adb pull "$1" "$dest/$(echo "$1" | tr / _)" >/dev/null || warn "could not pull $1"
	fi
}

# In TWRP the partitions might not be mounted yet.
adb shell 'mount /firmware 2>/dev/null; mount /system 2>/dev/null; mount /vendor 2>/dev/null; true'
adb shell 'mkdir -p /tmp/gemini-modem && mount -t vfat -o ro /dev/block/bootdevice/by-name/modem /tmp/gemini-modem 2>/dev/null; true'

for d in /firmware/image /tmp/gemini-modem/image /vendor/firmware /system/vendor/firmware \
         /system/etc/firmware /system/system/etc/firmware /system/system/vendor/firmware; do
	pull_dir "$d"
done
adb shell 'umount /tmp/gemini-modem 2>/dev/null; true'

log "Building .mbn files"
python3 -I "${TOP_DIR}/rootfs-overlay/usr/local/sbin/gemini-firmware-install" \
	--from "$dest" --dest "${FIRMWARE_DIR}"
rm -rf "$dest"
ls -l "${FIRMWARE_DIR}"
log "Firmware will be included in the next image build."
