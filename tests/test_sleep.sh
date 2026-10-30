#!/usr/bin/env bash
# gemini-sleep against a fake sysfs and systemctl: automatic sleep only with
# the screen off long enough and nothing keeping the phone awake, a backoff
# after a failed attempt, and AUTO_SLEEP switched off when a sleep never woke.
set -euo pipefail
tool="$(cd "$(dirname "$0")" && pwd)/../rootfs-overlay/usr/local/sbin/gemini-sleep"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GEMINI_SYS="$T/sys" GEMINI_CONF="$T/gemini" GEMINI_SLEEP_STATE="$T/lib"
export GEMINI_RUN="$T/run" GEMINI_SYSTEMCTL="$T/systemctl"
S="$T/sys/power/suspend_stats"; BL="$T/sys/class/backlight/wled"; USB="$T/sys/class/power_supply/usb"
mkdir -p "$S" "$BL" "$USB" "$T/bin"
echo 0 > "$S/success"; echo 0 > "$S/fail"
echo 0 > "$BL/bl_power"; echo USB > "$USB/type"
# no process is running, no ssh (pgrep/ss stubs first in PATH)
printf '#!/bin/sh\nexit 1\n' > "$T/bin/pgrep"; printf '#!/bin/sh\n[ -e %s/ssh ] && echo x\nexit 0\n' "$T" > "$T/bin/ss"
chmod +x "$T/bin/"*; export PATH="$T/bin:$PATH"

# systemctl suspend runs the hooks and counts a success, or a failure
cat > "$GEMINI_SYSTEMCTL" <<EOF
#!/bin/sh
[ "\$1" = suspend ] || exit 0
echo suspend >> "$T/calls"
"$tool" pre suspend
if [ -e "$T/kernel-refuses" ]; then
	echo \$((\$(cat "$S/fail") + 1)) > "$S/fail"; echo msm_drm > "$S/last_failed_dev"
else
	echo \$((\$(cat "$S/success") + 1)) > "$S/success"
fi
"$tool" post suspend
EOF
chmod +x "$GEMINI_SYSTEMCTL"

check() { [ "$1" = "$2" ] || { echo "FAIL: $3: got '$1', want '$2'"; exit 1; }; }
calls() { [ -e "$T/calls" ] && wc -l < "$T/calls" || echo 0; }
screen() { echo "$1" > "$BL/brightness"; }
power() { echo "$1" > "$USB/online"; }
auto() { "$tool" auto >/dev/null; }
ago() { echo $(( $(date +%s) - $1 * 60 )) > "$T/run/off-since"; }

echo "AUTO_SLEEP=0" > "$GEMINI_CONF"; screen 0; power 0
auto; auto
check "$(calls)" 0 "AUTO_SLEEP=0 never sleeps"

echo "AUTO_SLEEP=10" > "$GEMINI_CONF"
screen 100; auto
check "$(calls)" 0 "screen on"
screen 0; auto
check "$(calls)" 0 "screen just turned off"
ago 9; auto
check "$(calls)" 0 "9 of 10 minutes"
ago 10; power 1; auto
check "$(calls)" 0 "on a charger"
power 0; touch "$T/ssh"; auto
check "$(calls)" 0 "ssh session"
rm "$T/ssh"; printf '#!/bin/sh\n[ "$2" = claude ]\n' > "$T/bin/pgrep"; auto
check "$(calls)" 0 "Claude Code running"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/pgrep"; auto
check "$(calls)" 1 "screen off 10 min on battery -> sleep"
[ ! -e "$T/lib/sleep-pending" ] || { echo "FAIL: marker left after waking"; exit 1; }
auto
check "$(calls)" 1 "after waking, the 10 minutes start again"

# the kernel refuses (a driver failed to suspend): back off for 30 minutes
touch "$T/kernel-refuses"; ago 10; auto
check "$(calls)" 2 "attempt that fails"
ago 20; auto
check "$(calls)" 2 "no retry within 30 minutes"
"$tool" now >/dev/null && { echo "FAIL: 'now' must report the failure"; exit 1; }
rm "$T/kernel-refuses"
"$tool" now >/dev/null || { echo "FAIL: 'now' should succeed"; exit 1; }

# a sleep that never woke up: the next boot turns automatic sleep off
"$tool" pre suspend
"$tool" boot >/dev/null
check "$(sed -n 's/^AUTO_SLEEP=//p' "$GEMINI_CONF")" 0 "AUTO_SLEEP off after a failed wake"
[ -s "$T/lib/sleep-failed" ] || { echo "FAIL: failed wake not recorded"; exit 1; }
[ ! -e "$T/lib/sleep-pending" ] || { echo "FAIL: marker not cleared at boot"; exit 1; }
"$tool" boot >/dev/null
check "$(sed -n 's/^AUTO_SLEEP=//p' "$GEMINI_CONF")" 0 "normal boot changes nothing"
echo "sleep test passed"
