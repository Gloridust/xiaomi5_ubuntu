# Ubuntu 26.04 LTS for the Xiaomi Mi 5 (gemini)

Run **Ubuntu Server 26.04 "Resolute Raccoon"** (arm64) natively on a Xiaomi Mi 5,
with a mainline-based Linux kernel, WiFi, Bluetooth, USB networking, battery
support and a **touch GUI with an on-screen keyboard** (sway, GPU-accelerated),
so the phone works on its own as a small server, for example to run **Claude Code**.

- Install from **TWRP** with one zip (or with fastboot)
- Boots straight into a **touch terminal**: sway + foot + wvkbd keyboard,
  rendered by the Adreno 530 (Mesa freedreno), Chinese fonts, a status bar
  with CPU / RAM / GPU / WiFi / battery
- A **text menu** (`menu`) and easy commands (`wifi`, `status`, `install-claude`, `install-pi`)
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
| UI / keyboard | sway + foot terminal + `wvkbd` (default), or `buffyboard` on the text console, or phosh + `squeekboard` |

## Hardware support

| Component | Driver | Status |
|---|---|---|
| CPU (4 cores), frequency scaling, thermal | cpufreq-dt + kryo clocks, PM8994 S11 (SAW), tsens | ⚠️ 307 MHz – 2.15 GHz, needs testing on a Mi 5 ² |
| Storage (UFS) | ufs-qcom (built in) | ✅ upstream |
| Display 1080×1920 | msm DRM + `panel-jdi-fhd-r63452` | ✅ tested on a Mi 5 |
| Backlight | qcom-wled | ✅ upstream |
| Touchscreen | Synaptics RMI4 (I²C) | ✅ tested on a Mi 5 |
| **WiFi** 802.11ac | QCA6174 on PCIe, `ath10k_pci` + linux-firmware | ✅ tested on a Mi 5 ⁴ |
| **Bluetooth** 4.2 | QCA6174 UART, `hci_uart` + linux-firmware | ✅ tested on a Mi 5 (MAC from Android's persist) |
| USB 2.0 device mode | dwc3 → **USB network + serial console** to a PC | ✅ tested on a Mi 5 ³ |
| USB OTG host (keyboard, disks) | dwc3 + TUSB320L type-C + PMI8994 VBUS | ✅ |
| Battery level, charging | PMI8994 fuel gauge + smbchg (msm8996-mainline) | ✅ fork patches |
| Buttons (power, volume, home) | pm8941-pwrkey, gpio-keys | ✅ upstream |
| GPU Adreno 530 (OpenGL ES 3.2 / Vulkan) | msm + Mesa freedreno | ✅ tested on a Mi 5 (sway renders with it), needs device firmware ¹ |
| Audio: speaker, earpiece, headset | ADSP + WCD9335, UCM config included | ⚠️ needs device firmware ¹ |
| Video decode/encode | venus | ⚠️ needs device firmware ¹ |
| Modem (LTE data, SMS) | q6v5-mss + rmtfs + ModemManager | ⚠️ needs device firmware ¹, experimental |
| Vibrator, notification LED, button LEDs, IR blaster | drv2604, LPG, lp5562, pwm-ir-tx | ✅ upstream |
| NFC | nxp-nci | ⚠️ driver only, untested |
| Sensors: accel, gyro, compass, proximity, barometer | SLPI DSP, `qcom_sns_reg` + `qcom_smgr` IIO | ✅ tested on a Mi 5, needs device firmware ¹ (`gemini-sensors`) |
| Clock (keeps time while off) | pm8xxx RTC + saved offset (`gemini-rtc-offset`) | ✅ tested on a Mi 5 |
| Sleep (suspend to idle) | s2idle; wakes on power key, volume up, Home, charger | ⚠️ opt-in (`phone-sleep`), needs testing on a Mi 5 ⁵ |
| Cameras, fingerprint, deep sleep (suspend to RAM) | – | ❌ not supported |

¹ The GPU zap shader and DSP/modem firmware are signed by Xiaomi and cannot
be redistributed. **The phone copies them from its own Android partitions on
first boot** (`gemini-firmware-install`), or you can bake them in at build
time (see [docs/FIRMWARE.md](docs/FIRMWARE.md)).

² Kernel patch 0005 gives the CPU clocks voltages (the downstream kernel's
safe maximums, as mainline has no CPR driver for this chip). Changing the clock
without them locked up the phone. Scaling starts after boot, with a guard: if
the phone hangs or restarts within 10 minutes, the next boot uses a slower
level (`cpu full` → `safe` → `off`). See [docs/HARDWARE.md](docs/HARDWARE.md#cpu-speed).
³ The USB PHY sometimes fails to start at boot; `gemini-usb-gadget` retries.
⁴ The PCIe link to the WiFi chip sometimes doesn't train at boot;
`gemini-pcie-retrain` brings it back.
⁵ Off by default (a server should stay reachable). If a sleep never wakes up,
automatic sleep turns itself off. See [docs/HARDWARE.md](docs/HARDWARE.md#sleep).

> **Status:** boots to a working Ubuntu 26.04 login on a real Mi 5 (display,
> touch keyboard, USB network + SSH, storage, battery charging, WiFi,
> Bluetooth, sensors and the clock tested). Other rows marked "upstream" come from the upstream
> kernel / postmarketOS work on the same hardware and are not tested here yet.
> The build also boots in QEMU (`tests/qemu-boot.sh`).

## Quick start

1. Download `ubuntu-26.04-xiaomi-gemini-twrp.zip` from the latest
   [release](https://github.com/Gloridust/xiaomi5_ubuntu/releases/latest) (built and boot-tested automatically).
2. TWRP → Advanced → ADB Sideload, then `adb sideload ubuntu-26.04-xiaomi-gemini-twrp.zip`
   (or TWRP → Install → the zip). This **erases Android's user data**.
3. Reboot. The phone starts into a terminal with the on-screen keyboard.
   The first `sudo` asks for the password **ubuntu** and makes you choose a new one
   (SSH logins ask too).
4. The menu opens: **WiFi → Connect to a network**.
5. `install-claude`, then `claude`. Or `install-pi` (DeepSeek), then `pi`.

Easy commands: [docs/COMMANDS.md](docs/COMMANDS.md). From a PC over USB:
`ssh ubuntu@172.16.42.1`.

Build it yourself on an Ubuntu 24.04+ PC (~20 GB disk, 1–2 h):
`sudo ./build.sh && sudo scripts/40-make-twrp-zip.sh` (default `UI=sway`;
`UI=console` needs the least RAM, `UI=phosh` is a full phone shell).

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
| `gemini-sway.service` | the touch session: sway + terminal + wvkbd keyboard on tty7 (`UI=sway`) |
| `gemini-sway-screen`, `gemini-sway-idle`, `gemini-bar-status` | sway: power key / idle screen-off, status bar |
| `buffyboard.service` | on-screen keyboard on the text console (`UI=console`) |
| `gemini-powerkey` | text console: power key toggles the screen; auto screen-off after 2 min |
| `gemini-bt-mac` | gives the Bluetooth controller a stable MAC address |
| `gemini-status` / `status` | one-screen hardware overview |
| `menu`, `wifi`, `install-claude`, `install-pi`, `phone-help` | text menu and easy commands ([docs/COMMANDS.md](docs/COMMANDS.md)) |
| `gemini-wifi-watchdog.timer` | reconnects WiFi, resets the driver, starts a rescue hotspot |
| `gemini-firstboot` | grows the root filesystem, creates SSH host keys |

## Credits

Kernel and device tree work by the [msm8996-mainline](https://gitlab.com/msm8996-mainline)
project, Raffaele Tranquillini (Mi 5 device tree), Yassine Oudjana and the
[postmarketOS](https://postmarketos.org) community, whose kernel config and
ALSA UCM files are reused here. Buffyboard is from the postmarketOS
[buffybox](https://gitlab.postmarketos.org/postmarketOS/buffybox) project.
