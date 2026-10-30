#!/usr/bin/env bash
# Run the TWRP installer from a real zip under busybox (TWRP's tool set),
# against fake boot/userdata/modem partitions (image files), and check:
#   - Ubuntu rootfs + boot image are written
#   - device firmware is saved into the new rootfs (lower-cased names)
#   - the old boot image is kept
#   - a non-Mi 5 is refused without touching anything
# Needs root (loop mounts) and busybox-static.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); top="$here/.."
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
BB=$(command -v busybox) || { echo "install busybox-static"; exit 1; }
T=$(mktemp -d); trap 'umount "$T"/m 2>/dev/null || true; rm -rf "$T"' EXIT

# --- a tiny "Ubuntu" rootfs and boot image -------------------------------
mkdir -p "$T/rootdir/etc" "$T/out"
echo "test rootfs" > "$T/rootdir/etc/hello"
truncate -s 48M "$T/out/rootfs.img"
mkfs.ext4 -q -L gemini-root -d "$T/rootdir" "$T/out/rootfs.img"
head -c 3000000 /dev/urandom > "$T/out/boot.img"
OUT_DIR="$T/out" bash "$top/scripts/40-make-twrp-zip.sh" >/dev/null
ZIP="$T/out/ubuntu-26.04-xiaomi-gemini-twrp.zip"

# --- fake phone partitions -------------------------------------------------
mkdev() {
	head -c "$2" /dev/zero | tr '\0' "$3" > "$T/$1"
}
mkdev boot 8388608 B; cp "$T/boot" "$T/boot.orig"
mkdev userdata 67108864 D
# The real modem partition is FAT; the installer falls back to auto-detect,
# so an ext4 image works too (CI/sandbox kernels may lack vfat).
mkdir -p "$T/modemdir/image" "$T/m"
echo adsp-mdt > "$T/modemdir/image/ADSP.MDT"; echo adsp-b00 > "$T/modemdir/image/ADSP.B00"
echo mba > "$T/modemdir/image/MBA.MBN"; echo junk > "$T/modemdir/image/OTHER.BIN"
truncate -s 16M "$T/modem"; mkfs.ext4 -q -d "$T/modemdir" "$T/modem"
mkdir -p "$T/vendor/firmware"; echo zap > "$T/vendor/firmware/a530_zap.mdt"

# busybox-only PATH, like TWRP
mkdir -p "$T/bin"
for a in sh unzip gunzip dd mount umount tr cat wc df awk grep readlink basename \
         mkdir cp rm ls sync date echo blockdev head; do ln -s "$BB" "$T/bin/$a"; done

run() {
	env -i PATH="$T/bin" GEMINI_BOOT_DEV="$T/boot" GEMINI_DATA_DEV="$T/userdata" \
		GEMINI_MODEM_DEV="$T/modem" GEMINI_TMP="$T/tmp" GEMINI_SKIP_SYSTEM_MOUNT=1 \
		GEMINI_FW_DIRS="$T/vendor/firmware" "$@" \
		"$BB" sh "$top/twrp/update-binary" 3 1 "$ZIP"
}

# --- 1. wrong device: refused, nothing changed ----------------------------
if run > "$T/log1" 2>&1; then cat "$T/log1"; echo "FAIL: installed on a non-Mi 5"; exit 1; fi
grep -q 'only for the Xiaomi Mi 5' "$T/log1" || { cat "$T/log1"; echo "FAIL: device check"; exit 1; }
cmp -s "$T/boot" "$T/boot.orig" || { echo "FAIL: boot changed on refusal"; exit 1; }

# --- 2. real install --------------------------------------------------------
run GEMINI_SKIP_DEVICE_CHECK=1 > "$T/log2" 2>&1 || { cat "$T/log2"; echo "FAIL: install"; exit 1; }
sed -n 's/^ui_print //p' "$T/log2" | grep -v '^$'

cmp -s <(head -c 3000000 "$T/boot") "$T/out/boot.img" || { echo "FAIL: boot.img not written"; exit 1; }
mount -o loop,ro "$T/userdata" "$T/m"
check() { [ -e "$T/m/$1" ] || { echo "FAIL: missing $1"; umount "$T/m"; exit 1; }; }
check etc/hello
for f in adsp.mdt adsp.b00 mba.mbn a530_zap.mdt; do check "var/lib/gemini/firmware-stage/$f"; done
[ ! -e "$T/m/var/lib/gemini/firmware-stage/other.bin" ] || { echo "FAIL: copied unrelated file"; exit 1; }
cmp -s "$T/m/var/lib/gemini/android-boot.img" "$T/boot.orig" || { echo "FAIL: android boot backup"; exit 1; }
umount "$T/m"
echo "TWRP zip test passed"
