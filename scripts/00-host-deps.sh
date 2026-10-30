#!/usr/bin/env bash
# Install everything needed on an Ubuntu/Debian x86_64 (or arm64) build host.
source "$(dirname "$0")/lib.sh"
need_root

export DEBIAN_FRONTEND=noninteractive
pkgs=(git curl ca-certificates xz-utils zstd cpio kmod rsync file
	build-essential bc bison flex libssl-dev libelf-dev dwarves python3
	dpkg-dev debhelper fakeroot
	debootstrap ubuntu-keyring arch-test
	android-sdk-libsparse-utils e2fsprogs device-tree-compiler)
if [ "$(uname -m)" = aarch64 ]; then
	pkgs+=(gcc)          # native compiler also answers to aarch64-linux-gnu-gcc
else
	pkgs+=(gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu libc6-dev-arm64-cross
		qemu-user-static binfmt-support)
fi
apt-get update
apt-get install -y --no-install-recommends "${pkgs[@]}"
# mmdebstrap relies on its Recommends (arch-test, apt-utils, gpg...) for
# foreign-architecture builds, so install it with them.
apt-get install -y mmdebstrap

# Make sure arm64 binaries can run in the chroot (containers often lack this).
if [ "$(uname -m)" != aarch64 ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	[ -e /proc/sys/fs/binfmt_misc/register ] || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
	if [ -f /usr/lib/binfmt.d/qemu-aarch64.conf ]; then
		cat /usr/lib/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register
	else
		update-binfmts --enable qemu-aarch64
	fi
fi
[ "$(uname -m)" = aarch64 ] || [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] \
	|| die "qemu-aarch64 binfmt handler is not registered"
log "Host is ready."
