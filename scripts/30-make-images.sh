#!/usr/bin/env bash
# Pack work/rootfs into flashable images:
#   out/boot.img             -> fastboot flash boot
#   out/rootfs.img           raw ext4 (label gemini-root)
#   out/rootfs.sparse.img    -> fastboot flash userdata
source "$(dirname "$0")/lib.sh"
need_root
need_cmd mkfs.ext4 img2simg e2fsck

[ -d "${ROOTFS_DIR}/etc" ] || die "no rootfs in ${ROOTFS_DIR} - run scripts/20-build-rootfs.sh"

boot=$(readlink -f "${ROOTFS_DIR}/boot/boot.img" 2>/dev/null || true)
[ -f "$boot" ] || die "rootfs has no /boot/boot.img (kernel install hook failed?)"
cp "$boot" "${OUT_DIR}/boot.img"
size=$(stat -c %s "${OUT_DIR}/boot.img")
[ "$size" -le "${BOOT_PARTITION_MAX_BYTES}" ] || die "boot.img is $size bytes, boot partition holds ${BOOT_PARTITION_MAX_BYTES}"
log "boot.img: $((size / 1024 / 1024)) MiB"

log "Creating ext4 image (${ROOTFS_IMAGE_SIZE}, label ${ROOTFS_LABEL})"
rm -f "${OUT_DIR}/rootfs.img" "${OUT_DIR}/rootfs.sparse.img"
truncate -s "${ROOTFS_IMAGE_SIZE}" "${OUT_DIR}/rootfs.img"
mkfs.ext4 -q -F -L "${ROOTFS_LABEL}" -b 4096 -m 1 -E root_owner=0:0 \
	-d "${ROOTFS_DIR}" "${OUT_DIR}/rootfs.img"
e2fsck -fy "${OUT_DIR}/rootfs.img" >/dev/null || [ $? -le 1 ] || die "e2fsck reported errors"

log "Converting to Android sparse image"
img2simg "${OUT_DIR}/rootfs.img" "${OUT_DIR}/rootfs.sparse.img"

( cd "${OUT_DIR}" && sha256sum boot.img rootfs.sparse.img > SHA256SUMS )
log "Images in ${OUT_DIR}:"
ls -lh "${OUT_DIR}"/boot.img "${OUT_DIR}"/rootfs.sparse.img
