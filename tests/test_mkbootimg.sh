#!/usr/bin/env bash
# Run gemini-mkbootimg against a fake root and check the boot image header
# matches what the Mi 5 bootloader expects.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../rootfs-overlay/usr/local/sbin/gemini-mkbootimg"
# use the bundled AOSP tools (Ubuntu 24.04's mkbootimg package is broken)
export PATH="$here/../tools/mkbootimg:$PATH"
R=$(mktemp -d); trap 'rm -rf "$R"' EXIT
ver=6.19.5-gemini

mkdir -p "$R/boot" "$R/etc/default" "$R/usr/lib/linux-image-$ver/qcom"
head -c 3000000 /dev/urandom > "$R/boot/vmlinuz-$ver"          # uncompressed "Image"
head -c 500000 /dev/urandom | gzip > "$R/boot/initrd.img-$ver"
printf '/dts-v1/;\n/ { model = "test"; compatible = "xiaomi,gemini"; };\n' |
	dtc -q -I dts -O dtb -o "$R/usr/lib/linux-image-$ver/qcom/msm8996-xiaomi-gemini.dtb"
echo 'KERNEL_CMDLINE="root=LABEL=gemini-root rootwait rw console=tty0"' > "$R/etc/default/gemini"

GEMINI_ROOT="$R" "$tool" "$ver" "$R/boot/initrd.img-$ver"
[ "$(readlink "$R/boot/boot.img")" = "boot.img-$ver" ]

info=$(unpack_bootimg --boot_img "$R/boot/boot.img-$ver" --out "$R/unpacked" --format=mkbootimg)
echo "$info"
check() { echo "$info" | grep -q -- "$1" || { echo "FAIL: missing $1"; exit 1; }; }
check "--header_version 0"
# unpack_bootimg prints absolute load addresses (base 0x80000000 + offset)
check "--kernel_offset 0x80008000"
check "--ramdisk_offset 0x81000000"
check "--tags_offset 0x80000100"
check "--pagesize 0x00001000"
check "root=LABEL=gemini-root"

# kernel = gzip(Image) + dtb appended
k="$R/unpacked/kernel"
dtbsize=$(stat -c %s "$R/usr/lib/linux-image-$ver/qcom/msm8996-xiaomi-gemini.dtb")
tail -c "$dtbsize" "$k" | cmp - "$R/usr/lib/linux-image-$ver/qcom/msm8996-xiaomi-gemini.dtb"
head -c -"$dtbsize" "$k" | gzip -dc | cmp - "$R/boot/vmlinuz-$ver"
cmp "$R/unpacked/ramdisk" "$R/boot/initrd.img-$ver"
echo "mkbootimg test passed"
