#!/usr/bin/env bash
# gemini-cpufreq against a fake sysfs: speed levels, and the crash guard that
# drops a level when a boot with scaling never finished.
set -euo pipefail
tool="$(cd "$(dirname "$0")" && pwd)/../rootfs-overlay/usr/local/sbin/gemini-cpufreq"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GEMINI_SYS="$T/sys" GEMINI_CONF="$T/gemini" GEMINI_CPUFREQ_STATE="$T/state/cpufreq"
export GEMINI_CMDLINE="$T/cmdline" GEMINI_MODPROBE="$T/modprobe" CONFIRM_AFTER=0
P="$T/sys/devices/system/cpu/cpufreq"
echo "root=LABEL=gemini-root cpufreq.default_governor=powersave" > "$GEMINI_CMDLINE"

# "loading the driver" creates the two Kryo policies
cat > "$GEMINI_MODPROBE" <<EOF
#!/bin/sh
echo "\$1" >> "$T/loaded"
[ "\$1" = qcom-cpufreq-nvmem ] || exit 0
for p in 0:1593600:"0 1" 2:2150400:"2 3"; do
	d="$P/policy\${p%%:*}"; mkdir -p "\$d"
	r=\${p#*:}; echo "\${r%%:*}" > "\$d/cpuinfo_max_freq"; echo "\${r#*:}" > "\$d/related_cpus"
	echo 307200 > "\$d/scaling_cur_freq"; echo powersave > "\$d/scaling_governor"
	echo "\${r%%:*}" > "\$d/scaling_max_freq"
done
EOF
chmod +x "$GEMINI_MODPROBE"

check() { [ "$1" = "$2" ] || { echo "FAIL: $3: got '$1', want '$2'"; exit 1; }; }
boot() { rm -rf "$T/sys" "$T/loaded"; mkdir -p "$P"; "$tool" run >/dev/null; }
crash() { rm -rf "$T/sys" "$T/loaded"; mkdir -p "$P"; CONFIRM_AFTER=1000 timeout 1 "$tool" run >/dev/null || true; }
max() { echo "$(cat "$P/policy0/scaling_max_freq") $(cat "$P/policy2/scaling_max_freq")"; }
gov() { cat "$P/policy0/scaling_governor"; }
state() { sed -n "s/^$1=//p" "$GEMINI_CPUFREQ_STATE"; }

echo "CPU_SPEED=full" > "$GEMINI_CONF"
boot
check "$(max)" "1593600 2150400" "full: every clock"
check "$(gov)" schedutil "full: schedutil"
check "$(state trying)" "" "full: confirmed"

sed -i 's/^CPU_SPEED=.*/CPU_SPEED=safe/' "$GEMINI_CONF"
boot
check "$(max)" "1228800 1248000" "safe: 905 mV clocks only"

echo "# no CPU_SPEED line" > "$GEMINI_CONF"
boot
check "$(max)" "1593600 2150400" "default is full"

echo "CPU_SPEED=off" > "$GEMINI_CONF"
boot
[ ! -e "$T/loaded" ] || { echo "FAIL: off must not load the drivers"; exit 1; }

# A boot that never confirms (the phone hung) -> the next boot drops a level
echo "CPU_SPEED=full" > "$GEMINI_CONF"
crash
check "$(state trying)" full "hang leaves 'trying' behind"
boot
check "$(state limit)" safe "after a hang at full: limited to safe"
check "$(max)" "1228800 1248000" "after a hang at full: safe clocks"
boot
check "$(max)" "1228800 1248000" "the limit stays"
crash
boot
check "$(state limit)" off "after a hang at safe: off"
[ ! -e "$T/loaded" ] || { echo "FAIL: limit off must not load the drivers"; exit 1; }
grep -q "Limited to:        off" <<<"$("$tool" status)" || { echo "FAIL: status shows the limit"; exit 1; }

# Choosing a level by hand lifts the limit
"$tool" set full
check "$(state limit)" full "set lifts the limit"
check "$(sed -n 's/^CPU_SPEED=//p' "$GEMINI_CONF")" full "set writes the config"
boot
check "$(max)" "1593600 2150400" "full again"

# A clean shutdown during the test window is not a hang
crash
"$tool" stop
boot
check "$(state limit)" full "clean stop: no penalty"

# cpufreq.off=1 left on an old kernel command line
echo "root=LABEL=gemini-root cpufreq.off=1" > "$GEMINI_CMDLINE"
out=$("$tool" run)
case "$out" in *"cpufreq.off=1"*) ;; *) echo "FAIL: cpufreq.off=1 not reported"; exit 1 ;; esac

# No cpufreq driver (QEMU): not a failure, nothing left to roll back
echo "root=LABEL=gemini-root" > "$GEMINI_CMDLINE"
printf '#!/bin/sh\nexit 1\n' > "$GEMINI_MODPROBE"
rm -rf "$T/sys"; mkdir -p "$P"
grep -q "no CPU frequency driver" <<<"$("$tool" run)" || { echo "FAIL: missing driver"; exit 1; }
check "$(state trying)" "" "missing driver: nothing to confirm"
echo "cpufreq test passed"
