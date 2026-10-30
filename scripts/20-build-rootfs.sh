#!/usr/bin/env bash
# Build the Ubuntu 26.04 arm64 root filesystem for the Mi 5 in work/rootfs.
#
# Optional environment:
#   UI=console|sway|phosh      on-screen keyboard / UI flavour (default console)
#   EXTRA_PACKAGES="a b c"     more Ubuntu packages to install
#   WIFI_SSID / WIFI_PASSWORD  pre-configure a WiFi network
#   SSH_AUTHORIZED_KEYS=file   install these keys for the default user
source "$(dirname "$0")/lib.sh"
source "${TOP_DIR}/config/packages.conf"
need_root
need_cmd mmdebstrap

kdeb=""
for f in "${OUT_DIR}"/linux-image-*.deb; do
	case "$f" in *-dbg_*) continue ;; esac
	[ -f "$f" ] && { kdeb="$f"; break; }
done
if [ -z "$kdeb" ]; then
	# NO_KERNEL=1 builds only the userspace (for testing the rootfs)
	[ "${NO_KERNEL:-0}" = 1 ] || die "no kernel package in ${OUT_DIR} - run scripts/10-build-kernel.sh first"
	warn "NO_KERNEL=1: building rootfs without a kernel (not bootable)"
fi

pkgs=("${PKGS_BASE[@]}")
case "$UI" in
	console) ;;
	sway)  pkgs+=("${PKGS_UI_SWAY[@]}") ;;
	phosh) pkgs+=("${PKGS_UI_PHOSH[@]}") ;;
	*) die "unknown UI '$UI' (console, sway, phosh)" ;;
esac
# shellcheck disable=SC2206
pkgs+=(${EXTRA_PACKAGES:-})

if [ "$(uname -m)" != aarch64 ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	die "qemu-aarch64 binfmt is not registered - run scripts/00-host-deps.sh"
fi

log "Building Ubuntu ${UBUNTU_SUITE} rootfs (UI=${UI}) in ${ROOTFS_DIR}"
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

comps="main restricted universe multiverse"
export TOP_DIR OUT_DIR FIRMWARE_DIR UI DEFAULT_USER DEFAULT_PASSWORD HOSTNAME_DEFAULT \
	LOCALE_DEFAULT TIMEZONE_DEFAULT KERNEL_CMDLINE DTB_NAME UBUNTU_SUITE UBUNTU_MIRROR \
	ROOTFS_LABEL WIFI_SSID="${WIFI_SSID:-}" WIFI_PASSWORD="${WIFI_PASSWORD:-}" \
	SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}" KERNEL_DEB="$kdeb"

retry mmdebstrap \
	--mode=root \
	--architectures=arm64 \
	--variant=minbase \
	--components="${comps// /,}" \
	--aptopt='APT::Install-Recommends "false"' \
	--aptopt='Acquire::Retries "5"' \
	--dpkgopt='path-exclude=/usr/share/doc/*' \
	--dpkgopt='path-include=/usr/share/doc/*/copyright' \
	--include="$(IFS=,; echo "${pkgs[*]}")" \
	--customize-hook="\"${SCRIPT_DIR}/rootfs-customize.sh\" \"\$1\"" \
	"${UBUNTU_SUITE}" "${ROOTFS_DIR}" \
	"deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE} ${comps}" \
	"deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE}-updates ${comps}" \
	"deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE}-security ${comps}"

log "Rootfs ready: $(du -sh "${ROOTFS_DIR}" | cut -f1)"
