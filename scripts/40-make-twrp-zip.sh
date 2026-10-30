#!/usr/bin/env bash
# Package out/boot.img + out/rootfs.img as a zip that TWRP can install:
#   out/ubuntu-26.04-xiaomi-gemini-twrp.zip
# (TWRP -> Install -> pick the zip, or: adb sideload <zip>)
source "$(dirname "$0")/lib.sh"
need_cmd python3 gzip

boot="${OUT_DIR}/boot.img"; rootfs="${OUT_DIR}/rootfs.img"
[ -f "$boot" ] && [ -f "$rootfs" ] || die "run scripts/30-make-images.sh first"
zipname="${TWRP_ZIP_NAME:-ubuntu-26.04-xiaomi-gemini-twrp.zip}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

log "Compressing rootfs for TWRP (gzip)"
if command -v pigz >/dev/null; then pigz -6 -c "$rootfs" > "$tmp/rootfs.img.gz"
else gzip -6 -c "$rootfs" > "$tmp/rootfs.img.gz"; fi
stat -c %s "$rootfs" > "$tmp/rootfs.size"

cat > "$tmp/README.txt" <<TXT
Ubuntu 26.04 for Xiaomi Mi 5 (gemini) - TWRP installer
Built $(date -u +%Y-%m-%d) from $(git -C "${TOP_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)

TWRP -> Install -> this zip   (or: adb sideload $zipname)
ERASES the userdata partition (Android apps and files).
System, vendor and modem partitions are not changed.
First login: ubuntu / ubuntu
TXT

log "Building ${zipname}"
python3 -I - "$tmp" "$boot" "${OUT_DIR}/${zipname}" "${TOP_DIR}/twrp" <<'PY'
import os, sys, zipfile
tmp, boot, out, twrp = sys.argv[1:5]
with zipfile.ZipFile(out + ".tmp", "w", zipfile.ZIP_DEFLATED, allowZip64=False) as z:
    def add(src, name, compress=True):
        info = zipfile.ZipInfo.from_file(src, name)
        info.compress_type = zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED
        info.external_attr = 0o755 << 16 if name.endswith("update-binary") else 0o644 << 16
        with open(src, "rb") as f, z.open(info, "w") as w:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                w.write(b)
    add(os.path.join(twrp, "update-binary"), "META-INF/com/google/android/update-binary")
    add(os.path.join(twrp, "updater-script"), "META-INF/com/google/android/updater-script")
    add(os.path.join(tmp, "README.txt"), "README.txt")
    add(os.path.join(tmp, "rootfs.size"), "rootfs.size")
    add(boot, "boot.img")
    add(os.path.join(tmp, "rootfs.img.gz"), "rootfs.img.gz", compress=False)
os.replace(out + ".tmp", out)
PY
ls -lh "${OUT_DIR}/${zipname}"
