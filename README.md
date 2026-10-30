# Ubuntu 26.04 LTS for the Xiaomi Mi 5 (gemini)

Run **Ubuntu Server 26.04 "Resolute Raccoon"** (arm64) natively on a Xiaomi Mi 5,
with a mainline-based Linux kernel, WiFi, Bluetooth, USB networking, battery
support and a **touch on-screen keyboard**, so the phone works on its own as a
small server, for example to run **Claude Code**.

- Install from **TWRP** with one zip (or with fastboot)
- A **text menu** (`menu`) and easy commands (`wifi`, `status`, `install-claude`)
- WiFi that **heals itself**: reconnects, resets the driver, and finally opens
  a rescue hotspot so you can always get back in
- Volume keys and Home button navigate the menu

| | |
|---|---|
| Phone | Xiaomi Mi 5 (`gemini`), Snapdragon 820 (MSM8996), 3 GB RAM, UFS |
| OS | Ubuntu 26.04 LTS arm64, official Ubuntu archive (`apt upgrade` works) |
| Kernel | [msm8996-mainline](https://gitlab.com/msm8996-mainline/linux) `v6.19.5-msm8996` (mainline + MSM8996 patches) |
| Boot | stock Xiaomi bootloader → Android boot image (kernel + DTB + Ubuntu initramfs) |
| Root FS | ext4 on the `userdata` partition, grows to ~24 GB on first boot |
| Keyboard | `buffyboard` on the text console (default), or sway + `wvkbd`, or phosh + `squeekboard` |

## Hardware support

| Component | Driver | Status |
|---|---|---|
| CPU (4 cores), cpufreq, thermal | qcom-cpufreq-nvmem, tsens | ✅ upstream |
| Storage (UFS) | ufs-qcom (built in) | ✅ upstream |
| Display 1080×1920 | msm DRM + `panel-jdi-fhd-r63452` | ✅ upstream |
| Backlight | qcom-wled | ✅ upstream |
| Touchscreen | Synaptics RMI4 (I²C) | ✅ upstream |
| **WiFi** 802.11ac | QCA6174 on PCIe, `ath10k_pci` + linux-firmware | ✅ upstream |
| **Bluetooth** 4.2 | QCA6174 UART, `hci_uart` + linux-firmware | ✅ (MAC set by `gemini-bt-mac`) |
| USB 2.0 device mode | dwc3 → **USB network + serial console** to a PC | ✅ |
| USB OTG host (keyboard, disks) | dwc3 + TUSB320L type-C + PMI8994 VBUS | ✅ |
| Battery level, charging | PMI8994 fuel gauge + smbchg (msm8996-mainline) | ✅ fork patches |
| Buttons (power, volume, home) | pm8941-pwrkey, gpio-keys | ✅ upstream |
| GPU Adreno 530 (OpenGL ES 3.2 / Vulkan) | msm + Mesa freedreno | ✅ needs device firmware ¹ |
| Audio: speaker, earpiece, headset | ADSP + WCD9335, UCM config included | ⚠️ needs device firmware ¹ |
| Video decode/encode | venus | ⚠️ needs device firmware ¹ |
| Modem (LTE data, SMS) | q6v5-mss + rmtfs + ModemManager | ⚠️ needs device firmware ¹, experimental |
| Vibrator, notification LED, button LEDs, IR blaster | drv2604, LPG, lp5562, pwm-ir-tx | ✅ upstream |
| NFC | nxp-nci | ⚠️ driver only, untested |
| Sensors (accel, gyro, light) | SLPI DSP | ❌ not supported |
| Cameras, fingerprint, suspend-to-RAM | – | ❌ not supported (phone stays awake; screen turns off) |

¹ The GPU zap shader and DSP/modem firmware are signed by Xiaomi and cannot
be redistributed. **The phone copies them from its own Android partitions on
first boot** (`gemini-firmware-install`), or you can bake them in at build
time (see [docs/FIRMWARE.md](docs/FIRMWARE.md)).

> **Status:** the full build (kernel, Ubuntu 26.04 rootfs, `boot.img`,
> rootfs image) runs end to end, and the resulting kernel + rootfs **boot to a
> working Ubuntu 26.04 login in QEMU** (`tests/qemu-boot.sh`: root found by
> label, first-boot setup, services, AppArmor, zram, clean poweroff). The
> phone-specific hardware can't be emulated, and the port has **not yet been
> booted on a physical Mi 5**. Driver status above comes from the upstream
> kernel / postmarketOS work on the same hardware. Please report what works
> on yours.

## Quick start

1. Download `ubuntu-26.04-xiaomi-gemini-twrp.zip` from the latest
   [release](https://github.com/Gloridust/xiaomi5_ubuntu/releases/latest) (built and boot-tested automatically).
2. TWRP → Advanced → ADB Sideload, then `adb sideload ubuntu-26.04-xiaomi-gemini-twrp.zip`
   (or TWRP → Install → the zip). This **erases Android's user data**.
3. Reboot. Log in **ubuntu / ubuntu** and choose a new password.
4. The menu opens: **WiFi → Connect to a network**.
5. `install-claude`, then `claude`.

Easy commands: [docs/COMMANDS.md](docs/COMMANDS.md). From a PC over USB:
`ssh ubuntu@172.16.42.1`.

Build it yourself on an Ubuntu 24.04+ PC (~20 GB disk, 1–2 h):
`sudo ./build.sh && sudo scripts/40-make-twrp-zip.sh` (`UI=sway` or `UI=phosh`
for a touch GUI; the default console UI needs the least RAM).

Full guide: [docs/INSTALL.md](docs/INSTALL.md) ·
Hardware details: [docs/HARDWARE.md](docs/HARDWARE.md) ·
Problems: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## Repository layout

```
build.sh                    build everything (runs scripts/00..30 in order)
config/device.conf          device, kernel, boot image and Ubuntu settings
config/packages.conf        Ubuntu packages per UI flavour
kernel/base.config          kernel config (postmarketOS msm8996 config)
kernel/ubuntu-gemini.config fragment for Ubuntu (AppArmor, snapd, systemd...)
kernel/patches/             optional extra kernel patches (*.patch)
scripts/00-host-deps.sh     install build tools on the PC
scripts/10-build-kernel.sh  build the kernel as Ubuntu .deb packages
scripts/20-build-rootfs.sh  mmdebstrap Ubuntu 26.04 arm64 + device setup
scripts/30-make-images.sh   boot.img + ext4/sparse rootfs image
scripts/40-make-twrp-zip.sh TWRP-installable zip (twrp/update-binary)
scripts/flash.sh            fastboot flashing with safety checks
scripts/extract-firmware.sh pull signed firmware from the phone with adb
rootfs-overlay/             files installed into the phone's filesystem
tests/                      automated tests incl. a QEMU boot test (run in CI)
tools/mkbootimg/            AOSP mkbootimg (Ubuntu 24.04's package is broken)
```

### Tools installed on the phone

| Command / service | What it does |
|---|---|
| `gemini-mkbootimg` | rebuilds `boot.img` and flashes it after every kernel/initramfs update (hooked into apt) |
| `gemini-firmware-install` | finds the signed firmware on the Android partitions and installs it |
| `gemini-usb-gadget` | USB network (`172.16.42.1`, DHCP for the PC) + USB serial console |
| `buffyboard.service` | on-screen keyboard on the text console |
| `gemini-powerkey` | power key toggles the screen; auto screen-off after 2 min |
| `gemini-bt-mac` | gives the Bluetooth controller a stable MAC address |
| `gemini-status` / `status` | one-screen hardware overview |
| `menu`, `wifi`, `install-claude`, `phone-help` | text menu and easy commands ([docs/COMMANDS.md](docs/COMMANDS.md)) |
| `gemini-wifi-watchdog.timer` | reconnects WiFi, resets the driver, starts a rescue hotspot |
| `gemini-firstboot` | grows the root filesystem, creates SSH host keys |

## Credits

Kernel and device tree work by the [msm8996-mainline](https://gitlab.com/msm8996-mainline)
project, Raffaele Tranquillini (Mi 5 device tree), Yassine Oudjana and the
[postmarketOS](https://postmarketos.org) community, whose kernel config and
ALSA UCM files are reused here. Buffyboard is from the postmarketOS
[buffybox](https://gitlab.postmarketos.org/postmarketOS/buffybox) project.
