#!/usr/bin/env bash
# Boot the built kernel + Ubuntu rootfs in QEMU (generic arm64 "virt"
# machine) and check that Ubuntu comes up: root found by label, first-boot
# setup, login with forced password change, services, clean poweroff.
# The phone's own hardware can't be emulated; this tests everything else.
#
#   sudo tests/qemu-boot.sh          (after build.sh / 30-make-images.sh)
set -euo pipefail
source "$(dirname "$0")/../scripts/lib.sh"
need_root
need_cmd qemu-system-aarch64 python3

Q="${WORK_DIR}/qemu"
rel=$(cat "${OUT_DIR}/kernel.release")
rm -rf "$Q"; mkdir -p "$Q"

# QEMU's disk is virtio, so the test initramfs also needs virtio_blk.
log "Building test initramfs (+virtio_blk)"
cp -a "${ROOTFS_DIR}/etc/initramfs-tools" "$Q/itools-backup"
printf 'virtio_blk\n' >> "${ROOTFS_DIR}/etc/initramfs-tools/modules"
for m in proc sys dev; do mount --bind "/$m" "${ROOTFS_DIR}/$m"; done
restore() {
	for m in dev sys proc; do umount "${ROOTFS_DIR}/$m" 2>/dev/null || true; done
	rm -rf "${ROOTFS_DIR}/etc/initramfs-tools"
	cp -a "$Q/itools-backup" "${ROOTFS_DIR}/etc/initramfs-tools"
}
trap restore EXIT
chroot "${ROOTFS_DIR}" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	mkinitramfs -o /tmp/initrd-qemu "$rel" 2>&1 | grep -v 'fsck hook' || true
mv "${ROOTFS_DIR}/tmp/initrd-qemu" "$Q/initrd"
restore; trap - EXIT

cp --sparse=always "${OUT_DIR}/rootfs.img" "$Q/disk.img"
log "Booting (software emulation, takes 5-15 minutes)"
python3 -I "$(dirname "$0")/qemu_boot_test.py" "${OUT_DIR}/Image.gz" "$Q/initrd" "$Q/disk.img" "$Q/console.log"
