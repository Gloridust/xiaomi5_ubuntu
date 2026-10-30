# Ubuntu 26.04 LTS for the Xiaomi Mi 5 (gemini)

Run **Ubuntu Server 26.04 "Resolute Raccoon"** (arm64) natively on a Xiaomi Mi 5,
with a mainline-based Linux kernel, WiFi, Bluetooth, USB networking, battery
support and a **touch on-screen keyboard** so the phone can be used on its own,
without a PC.

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

> **Status:** the Ubuntu 26.04 rootfs build, the kernel-install → initramfs →
> `boot.img` chain, the image packing and the firmware tooling have been run
> and tested; the kernel compile runs in the GitHub Actions workflow. The port
> has **not yet been booted on a physical Mi 5**. Driver status above comes
> from the upstream kernel / postmarketOS work on the same hardware. Please
> report what works on yours.

## Quick start

```bash
# On an Ubuntu 24.04+ PC (x86_64 or arm64), ~20 GB free disk:
git clone <this repo> && cd xiaomi5_ubuntu
sudo ./build.sh                    # kernel + Ubuntu rootfs + images  (UI=sway / UI=phosh for a GUI)

# Phone: unlocked bootloader, hold Power + Volume Down -> fastboot, plug USB
scripts/flash.sh                   # flashes boot + userdata (erases Android user data)
```

Or download `boot.img` and `rootfs.sparse.img.xz` from the GitHub Actions run /
release and run `IMAGES_DIR=~/Downloads scripts/flash.sh`.

First login: **ubuntu / ubuntu** (you must pick a new password). Then:

```bash
sudo nmtui                         # connect to WiFi
gemini-status                      # battery, WiFi, DSPs, firmware...
ssh ubuntu@172.16.42.1             # from a PC over the USB cable
```

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
scripts/flash.sh            fastboot flashing with safety checks
scripts/extract-firmware.sh pull signed firmware from the phone with adb
rootfs-overlay/             files installed into the phone's filesystem
tests/                      automated tests (run in CI)
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
| `gemini-status` | one-screen hardware overview |
| `gemini-firstboot` | grows the root filesystem, creates SSH host keys |

## Credits

Kernel and device tree work by the [msm8996-mainline](https://gitlab.com/msm8996-mainline)
project, Raffaele Tranquillini (Mi 5 device tree), Yassine Oudjana and the
[postmarketOS](https://postmarketos.org) community, whose kernel config and
ALSA UCM files are reused here. Buffyboard is from the postmarketOS
[buffybox](https://gitlab.postmarketos.org/postmarketOS/buffybox) project.
