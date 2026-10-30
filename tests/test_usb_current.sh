#!/usr/bin/env bash
# gemini-usb-current against a fake charger in sysfs: raises the limit only
# for a PC port (SDP) that is online, and only to what USB_PC_CURRENT allows.
set -euo pipefail
tool="$(cd "$(dirname "$0")" && pwd)/../rootfs-overlay/usr/local/sbin/gemini-usb-current"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GEMINI_CONF="$T/gemini"

run() {  # conf-value online usb_type -> resulting limit
	printf 'USB_PC_CURRENT=%s\n' "$1" > "$GEMINI_CONF"
	echo "$2" > "$T/online"; echo "$3" > "$T/usb_type"; echo 500000 > "$T/input_current_limit"
	"$tool" "$T" >/dev/null
	cat "$T/input_current_limit"
}
check() { [ "$1" = "$2" ] || { echo "FAIL: $3: got $1, want $2"; exit 1; }; }

check "$(run 900 1 'Unknown [SDP] DCP CDP')" 900000 "PC port, 900"
check "$(run 500 1 'Unknown [SDP] DCP CDP')" 500000 "PC port, 500"
check "$(run 900 1 'Unknown SDP [DCP] CDP')" 500000 "wall charger untouched"
check "$(run 900 0 'Unknown [SDP] DCP CDP')" 500000 "unplugged"
check "$(run 2000 1 'Unknown [SDP] DCP CDP')" 500000 "out-of-range value ignored"
check "$(run '' 1 'Unknown [SDP] DCP CDP')" 500000 "unset"
echo "usb-current test passed"
