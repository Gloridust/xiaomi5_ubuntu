#!/usr/bin/env bash
# Build the msm8996-mainline kernel for the Mi 5 and package it as Ubuntu .debs.
#
# Output (in out/):
#   linux-image-<rel>_*.deb    kernel, modules, device trees
#   Image.gz, msm8996-xiaomi-gemini.dtb, kernel.release
source "$(dirname "$0")/lib.sh"
need_cmd git make "${CROSS_COMPILE}gcc" dpkg-buildpackage

if [ ! -d "${KERNEL_SRC}/.git" ] && [ ! -f "${KERNEL_SRC}/Makefile" ]; then
	log "Cloning ${KERNEL_REPO} (${KERNEL_TAG})"
	retry git clone --depth 1 -b "${KERNEL_TAG}" "${KERNEL_REPO}" "${KERNEL_SRC}"
fi

# Local patches on top of the kernel tree (kernel/patches/*.patch), applied once.
if compgen -G "${TOP_DIR}/kernel/patches/*.patch" >/dev/null; then
	for p in "${TOP_DIR}"/kernel/patches/*.patch; do
		if git -C "${KERNEL_SRC}" apply --check "$p" 2>/dev/null; then
			log "Applying $(basename "$p")"
			git -C "${KERNEL_SRC}" apply "$p"
		elif git -C "${KERNEL_SRC}" apply --check -R "$p" 2>/dev/null; then
			log "Already applied: $(basename "$p")"
		else
			die "patch does not apply: $p"
		fi
	done
fi

mkdir -p "${KERNEL_BUILD}"
MAKE=(make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE}"
	-j"$(nproc)" KBUILD_BUILD_USER=ubuntu KBUILD_BUILD_HOST=gemini)

log "Configuring kernel"
cp "${TOP_DIR}/kernel/base.config" "${KERNEL_BUILD}/.config"
"${KERNEL_SRC}/scripts/kconfig/merge_config.sh" -m -O "${KERNEL_BUILD}" \
	"${KERNEL_BUILD}/.config" "${TOP_DIR}/kernel/ubuntu-gemini.config" >/dev/null
sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"${KERNEL_LOCALVERSION}\"|" "${KERNEL_BUILD}/.config"
"${MAKE[@]}" olddefconfig >/dev/null

# Report fragment options that Kconfig silently dropped (typos, missing deps).
missing=0
while IFS= read -r line; do
	case "$line" in ''|\#*) continue ;; esac
	key="${line%%=*}"
	[ "$key" = CONFIG_LOCALVERSION ] && continue
	if ! grep -qx -- "$line" "${KERNEL_BUILD}/.config"; then
		got=$(grep -E "^(# )?${key}[= ]" "${KERNEL_BUILD}/.config" || echo "(unknown symbol)")
		warn "fragment wants '$line', got '$got'"
		missing=$((missing + 1))
	fi
done < "${TOP_DIR}/kernel/ubuntu-gemini.config"
[ $missing -eq 0 ] || warn "$missing fragment option(s) not applied (see above)"

log "Building kernel ($(nproc) jobs)"
"${MAKE[@]}" Image.gz modules dtbs

REL=$(kernel_release)
log "Kernel release: ${REL}"

log "Packaging .deb"
rm -f "${WORK_DIR}"/linux-*.deb "${WORK_DIR}"/linux-*.changes "${WORK_DIR}"/linux-*.buildinfo
# bindeb-pkg writes the .debs to the parent of the build dir (WORK_DIR)
"${MAKE[@]}" bindeb-pkg KDEB_PKGVERSION="${REL%%-*}-1" KDEB_COMPRESS=xz \
	DPKG_FLAGS="-d" >/dev/null

rm -f "${OUT_DIR}"/linux-*.deb
mv "${WORK_DIR}"/linux-image-"${REL}"_*.deb "${OUT_DIR}/"
mv "${WORK_DIR}"/linux-headers-"${REL}"_*.deb "${OUT_DIR}/" 2>/dev/null || true
mv "${WORK_DIR}"/linux-libc-dev_*.deb "${OUT_DIR}/" 2>/dev/null || true
rm -f "${WORK_DIR}"/linux-*.changes "${WORK_DIR}"/linux-*.buildinfo "${WORK_DIR}"/linux-*.deb

cp "${KERNEL_BUILD}/arch/arm64/boot/Image.gz" "${OUT_DIR}/Image.gz"
cp "${KERNEL_BUILD}/arch/arm64/boot/dts/${DTB_NAME}.dtb" "${OUT_DIR}/"
echo "${REL}" > "${OUT_DIR}/kernel.release"
cp "${KERNEL_BUILD}/.config" "${OUT_DIR}/config-${REL}"

log "Done: $(ls "${OUT_DIR}"/linux-image-*.deb)"
