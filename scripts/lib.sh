#!/usr/bin/env bash
# Shared helpers for the build scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/device.conf
source "${SCRIPT_DIR}/../config/device.conf"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "run as root (sudo $0)"; }

need_cmd() {
	local c
	for c in "$@"; do
		command -v "$c" >/dev/null 2>&1 || die "missing '$c' - run scripts/00-host-deps.sh"
	done
}

# Run a command, retrying network failures with backoff (2s 4s 8s 16s).
retry() {
	local n=0 delay=2
	until "$@"; do
		n=$((n + 1))
		[ $n -ge 5 ] && return 1
		warn "command failed, retry $n in ${delay}s: $*"
		sleep $delay
		delay=$((delay * 2))
	done
}

kernel_release() {
	cat "${KERNEL_BUILD}/include/config/kernel.release"
}

mkdir -p "${WORK_DIR}" "${OUT_DIR}"
