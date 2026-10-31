#!/usr/bin/env bash
# mmdebstrap customize hook: turn a plain Ubuntu chroot into the Mi 5 system.
# $1 = rootfs directory. Environment comes from 20-build-rootfs.sh.
set -euo pipefail
R="$1"
log() { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
in_root() { chroot "$R" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 "$@"; }

log "Copying rootfs overlay"
cp -a --no-preserve=ownership "${TOP_DIR}/rootfs-overlay/." "$R/"
chown -R root:root "$R/usr/local" "$R/etc/systemd" "$R/etc/udev/rules.d" \
	"$R/etc/NetworkManager/conf.d" "$R/etc/netplan" "$R/etc/initramfs-tools" \
	"$R/usr/share/alsa/ucm2" "$R/usr/lib/systemd/system-sleep/gemini"
chown root:root "$R"/etc/sudoers.d/gemini && chmod 0440 "$R"/etc/sudoers.d/gemini

log "Writing /etc/default/gemini"
cat > "$R/etc/default/gemini" <<EOF
# Xiaomi Mi 5 settings (read by gemini-* tools)

# Kernel command line baked into the boot image. After changing it run:
#   sudo gemini-mkbootimg --flash
KERNEL_CMDLINE="${KERNEL_CMDLINE}"
DTB="${DTB_NAME}.dtb"

# Write a new boot image to the boot partition automatically whenever the
# kernel or initramfs is updated (apt upgrade). Set to "no" to do it by hand.
FLASH_BOOT=yes

# Console UI: turn the screen off after this many idle seconds (0 = never)
SCREEN_TIMEOUT=120

# Volume up/down and Home button act as arrow up/down and Enter
KEY_REMAP=yes

# Charging from a PC's USB port: 500 (mA, USB 2.0) or 900 (USB 3.0 ports only;
# a USB 2.0 port may switch off). At 500 the phone can still discharge while
# plugged in. Takes effect on the next plug-in, or: sudo gemini-usb-current
USB_PC_CURRENT=500

# No WiFi for HOTSPOT_AFTER checks (2 min each) -> start a rescue hotspot,
# so you can join it from a laptop and ssh in. The password is created on
# first boot (HOTSPOT_PASSWORD below) and shown by:  wifi status
AUTO_HOTSPOT=yes
HOTSPOT_SSID="Mi5-Ubuntu"
HOTSPOT_AFTER=5

# CPU speed (or run: cpu full|safe|off)
#   full  up to 1.6 GHz (small cores) / 2.15 GHz (big cores)
#   safe  up to 1.2 GHz at a lower voltage: cooler, longer battery
#   off   no clock changes: the CPUs stay at the bootloader's 1 GHz
# If the phone hangs or restarts on its own within 10 minutes of a boot, the
# next boot uses one level lower until you choose again with "cpu".
CPU_SPEED=full

# Sleep after this many minutes with the screen off, on battery, with no ssh
# login and none of SLEEP_BLOCKERS running (0 = never; or: phone-sleep auto N).
# While asleep the phone is off the network; the power key wakes it.
AUTO_SLEEP=0
SLEEP_BLOCKERS="claude pi node apt apt-get dpkg unattended-upgr"
EOF

log "Hostname, hosts, fstab"
echo "${HOSTNAME_DEFAULT}" > "$R/etc/hostname"
cat > "$R/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	${HOSTNAME_DEFAULT}
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
cat > "$R/etc/fstab" <<EOF
# <file system>          <mount point> <type> <options>                 <dump> <pass>
LABEL=${ROOTFS_LABEL}    /             ext4   defaults,noatime,commit=30  0      1
EOF

log "APT sources (deb822)"
rm -f "$R/etc/apt/sources.list"
cat > "$R/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: ${UBUNTU_MIRROR}
Suites: ${UBUNTU_SUITE} ${UBUNTU_SUITE}-updates ${UBUNTU_SUITE}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: ${UBUNTU_MIRROR}
Suites: ${UBUNTU_SUITE}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
# Our kernel is the only one that boots on this phone: never pull Ubuntu's.
cat > "$R/etc/apt/preferences.d/gemini-no-generic-kernel" <<'EOF'
Package: linux-image-generic linux-generic linux-image-[0-9]*-generic flash-kernel
Pin: release *
Pin-Priority: -1
EOF

log "Locale ${LOCALE_DEFAULT}, timezone ${TIMEZONE_DEFAULT}, console font"
sed -i "s/^# *\(${LOCALE_DEFAULT} \)/\1/" "$R/etc/locale.gen" 2>/dev/null || true
grep -q "^${LOCALE_DEFAULT} " "$R/etc/locale.gen" 2>/dev/null || echo "${LOCALE_DEFAULT} UTF-8" >> "$R/etc/locale.gen"
in_root locale-gen
echo "LANG=${LOCALE_DEFAULT}" > "$R/etc/default/locale"
ln -sf "/usr/share/zoneinfo/${TIMEZONE_DEFAULT}" "$R/etc/localtime"
echo "${TIMEZONE_DEFAULT}" > "$R/etc/timezone"
cat > "$R/etc/default/console-setup" <<'EOF'
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="guess"
FONTFACE="Terminus"
FONTSIZE="16x32"
EOF
cat > "$R/etc/default/keyboard" <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

log "User ${DEFAULT_USER}"
if ! in_root id "${DEFAULT_USER}" >/dev/null 2>&1; then
	in_root useradd -m -s /bin/bash -c "Ubuntu" "${DEFAULT_USER}"
fi
for g in sudo adm video render input audio plugdev dialout netdev bluetooth; do
	in_root getent group "$g" >/dev/null && in_root usermod -aG "$g" "${DEFAULT_USER}"
done
echo "${DEFAULT_USER}:${DEFAULT_PASSWORD}" | in_root chpasswd
in_root chage -d 0 "${DEFAULT_USER}"   # must choose a new password at first login
in_root passwd -l root >/dev/null

if [ -n "${SSH_AUTHORIZED_KEYS}" ] && [ -f "${SSH_AUTHORIZED_KEYS}" ]; then
	log "Installing SSH authorized_keys"
	h="$R/home/${DEFAULT_USER}"
	install -d -m 700 "$h/.ssh"
	install -m 600 "${SSH_AUTHORIZED_KEYS}" "$h/.ssh/authorized_keys"
	in_root chown -R "${DEFAULT_USER}:${DEFAULT_USER}" "/home/${DEFAULT_USER}/.ssh"
fi

if [ -n "${WIFI_SSID}" ]; then
	log "Pre-configuring WiFi network '${WIFI_SSID}'"
	f="$R/etc/NetworkManager/system-connections/${WIFI_SSID//\//_}.nmconnection"
	{
		echo "[connection]"
		echo "id=${WIFI_SSID}"
		echo "type=wifi"
		echo "autoconnect=true"
		echo "[wifi]"
		echo "mode=infrastructure"
		echo "ssid=${WIFI_SSID}"
		if [ -n "${WIFI_PASSWORD}" ]; then
			echo "[wifi-security]"
			echo "key-mgmt=wpa-psk"
			echo "psk=${WIFI_PASSWORD}"
		fi
		echo "[ipv4]"
		echo "method=auto"
		echo "[ipv6]"
		echo "method=auto"
	} > "$f"
	chmod 600 "$f"
fi

log "Device firmware"
fwdst="$R/lib/firmware/qcom/msm8996/gemini"
mkdir -p "$fwdst"
if [ -d "${FIRMWARE_DIR}" ] && [ -n "$(ls -A "${FIRMWARE_DIR}" 2>/dev/null)" ]; then
	# Accepts ready .mbn files or raw .mdt/.bNN dumps.
	python3 -I "${TOP_DIR}/rootfs-overlay/usr/local/sbin/gemini-firmware-install" \
		--from "${FIRMWARE_DIR}" --dest "$fwdst"
else
	echo "     none in ${FIRMWARE_DIR}; the phone copies it from Android on first boot"
fi

log "Enabling services"
systemd_enable() { in_root systemctl enable "$@" >/dev/null 2>&1 || echo "     (could not enable $*)"; }
systemd_enable gemini-firstboot.service gemini-firmware.service gemini-usb-gadget.service \
	systemd-networkd.service NetworkManager.service \
	systemd-resolved.service bluetooth.service rmtfs.service \
	ModemManager.service gemini-wifi-watchdog.timer \
	gemini-rtc-offset.service gemini-rtc-offset-save.timer gemini-pcie-retrain.service \
	gemini-cpufreq.service gemini-sleep-check.service gemini-autosleep.timer
# Suspend (to idle) is allowed; there is nothing to hibernate to.
in_root systemctl mask systemd-networkd-wait-online.service NetworkManager-wait-online.service \
	systemd-firstboot.service hibernate.target hybrid-sleep.target \
	suspend-then-hibernate.target >/dev/null
in_root systemctl unmask sleep.target suspend.target >/dev/null 2>&1 || true   # masked by older builds
case "${UI}" in
console)
	systemd_enable buffyboard.service gemini-powerkey.service
	;;
sway)
	systemd_enable gemini-sway.service
	in_root systemctl set-default graphical.target >/dev/null
	sed -i '/buffyboard.service/d' "$R/etc/udev/rules.d/90-gemini.rules"
	;;
phosh)
	mkdir -p "$R/etc/systemd/system/phosh.service.d"
	cat > "$R/etc/systemd/system/phosh.service.d/gemini.conf" <<EOF
[Service]
User=${DEFAULT_USER}
EOF
	systemd_enable phosh.service
	in_root systemctl set-default graphical.target >/dev/null
	sed -i '/buffyboard.service/d' "$R/etc/udev/rules.d/90-gemini.rules"
	mkdir -p "$R/etc/phosh"
	printf '[output:DSI-1]\nscale = 2.5\n' > "$R/etc/phosh/phoc.ini"
	;;
esac
# Remove the GUI session files when the console UI is used
[ "${UI}" = sway ] || rm -f "$R/etc/systemd/system/gemini-sway.service" "$R/etc/pam.d/gemini-sway"

if [ -n "${KERNEL_DEB}" ]; then
	log "Installing kernel $(basename "${KERNEL_DEB}")"
	cp "${KERNEL_DEB}" "$R/tmp/"
	in_root apt-get install -y --no-install-recommends "/tmp/$(basename "${KERNEL_DEB}")"
	rm -f "$R/tmp/$(basename "${KERNEL_DEB}")"
	if ! ls "$R"/boot/boot.img-* >/dev/null 2>&1; then
		# make sure initramfs + boot image exist even if a hook was skipped
		rel=$(ls "$R/lib/modules" | sort -V | tail -n1)
		in_root update-initramfs -c -k "$rel"
	fi
	ls -l "$R"/boot/
else
	log "No kernel package: skipping kernel install"
fi

log "Cleaning up"
rm -f "$R"/etc/ssh/ssh_host_*            # regenerated per phone on first boot
: > "$R/etc/machine-id"                   # regenerated on first boot
rm -f "$R/var/lib/dbus/machine-id"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
in_root apt-get clean
rm -rf "$R"/var/lib/apt/lists/* "$R"/var/cache/apt/*.bin "$R"/tmp/* "$R"/var/tmp/* \
	"$R"/var/log/*.log "$R"/var/log/apt/* "$R"/root/.bash_history
mkdir -p "$R/var/lib/gemini"
date -u +%Y-%m-%dT%H:%MZ > "$R/etc/gemini-build"
