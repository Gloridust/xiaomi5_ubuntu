# Mi 5 hardware under Ubuntu

How each part of the phone is driven, and how to check it.

## Display, backlight, console font

- MSM8996 MDP5 display engine (`msm` DRM driver) + DSI + JDI R63452 panel
  (`panel-jdi-fhd-r63452`). Both modules are in the initramfs, so the screen
  works from early boot (disk checks, recovery shell).
- Backlight: PMI8994 WLED, `/sys/class/backlight/*`. Change with
  `brightnessctl set 40%` (no sudo needed for the `video` group).
- Console font Terminus 16×32 → 67 columns × 60 rows, minus the keyboard.

## On-screen keyboards

| UI | Keyboard | How it works |
|---|---|---|
| `console` | **buffyboard** | draws on the framebuffer, sends keys to the active console through `uinput`, and shrinks the console so text isn't hidden. Config: `/etc/buffyboard.conf.d/gemini.conf` (theme, layout). |
| `sway` (default) | **wvkbd-mobintl** | Wayland layer-shell keyboard. **Volume up** shows/hides it, **volume down** opens a new terminal. `Ctr`/`Alt` are sticky: tap `Ctr`, then `c` for Ctrl+C. Config: `/usr/local/share/gemini/sway/config`. |
| `phosh` | **squeekboard** | appears automatically in text fields. |

### The sway session

- Runs as `gemini-sway.service` on tty7, logged in as the default user with
  its own PAM stack (`/etc/pam.d/gemini-sway`): the image expires the first
  password, and the normal `login` stack would then refuse to start the
  session. Only starts when `/dev/dri/card0` exists.
- Rendered by the GPU (EGL on `/dev/dri/card0`, Mesa freedreno). foot falls
  back to WenQuanYi Micro Hei for Chinese text; 5000 lines of scrollback,
  drag with a finger to scroll.
- Status bar (`gemini-bar-status`, i3status plus the GPU clock):
  `CPU | RAM | GPU clock | WiFi name + signal | CHG/BAT battery | time`. The
  GPU clock goes from 133 MHz (idle) to 510 MHz (busy); its busy percentage
  is only in debugfs.
- **Power key**: screen off/on. Off = backlight 0 and touch disabled
  (`gemini-sway-screen`). Not sway's `output power off`: the msm driver
  rejects the atomic commit that disables the panel and the screen stays on.
  `screen-timeout` / `SCREEN_TIMEOUT` set the idle timeout (`gemini-sway-idle`).
- Screenshot: `grim shot.png` in the terminal.

Switch an installed console system to the sway GUI (from a checkout of this
repo, `rootfs-overlay` holds the files):

```bash
sudo apt install --no-install-recommends sway swaybg swayidle swaylock foot wvkbd i3status grim \
	fonts-dejavu-core fonts-wqy-microhei libgl1-mesa-dri libegl-mesa0 mesa-vulkan-drivers
sudo cp rootfs-overlay/etc/systemd/system/gemini-sway.service /etc/systemd/system/
sudo cp rootfs-overlay/etc/pam.d/gemini-sway /etc/pam.d/
sudo cp rootfs-overlay/usr/local/bin/{gemini-sway-screen,gemini-sway-idle,gemini-bar-status,phone-help,screen-timeout} /usr/local/bin/
sudo cp -r rootfs-overlay/usr/local/share/gemini/sway /usr/local/share/gemini/
sudo sed -i '/buffyboard.service/d' /etc/udev/rules.d/90-gemini.rules
sudo systemctl disable --now buffyboard gemini-powerkey
sudo systemctl enable gemini-sway && sudo systemctl set-default graphical.target && sudo reboot
```

## Touchscreen

Synaptics RMI4 over I²C (`rmi_i2c`, F12). Test with `sudo evtest` or
`sudo libinput debug-events`. If touches land in the wrong place, see
*Touch is offset* in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## WiFi

QCA6174A on PCIe, `ath10k_pci`. Firmware `ath10k/QCA6174/hw3.0/firmware-6.bin`
and `board-2.bin` come from Ubuntu's `linux-firmware-qualcomm-wireless`.
Managed by NetworkManager (`nmtui`, `nmcli`). Power saving is disabled in
`/etc/NetworkManager/conf.d/10-gemini.conf` because it makes ath10k laggy.

On some boots the PCIe link to the chip doesn't train in time
(`qcom-pcie 600000.pcie: Phy link never came up`) and the chip is missing.
`gemini-pcie-retrain.service` then retrains the link and rescans the bus, and
the WiFi watchdog does the same if it ever finds no WiFi device.

Check: `iw dev`, `dmesg | grep ath10k`, `lspci`.

## Bluetooth

Same QCA6174 chip, over UART (`hci_uart` with the QCA protocol). Firmware
`qca/rampatch_00130302.bin` + `qca/nvm_00130302.bin` from linux-firmware.
The chip has no MAC address of its own under Linux, so `gemini-bt-mac@hci0`
gives it the phone's real one from Android's `persist:/wlan_bt/bt.mac`
(cached in `/var/lib/gemini/bt-address`), or a stable one derived from the
serial number if that can't be read.

Check: `bluetoothctl show`, `bluetoothctl scan on`.

## USB

- **Device mode** (cable to a PC): `gemini-usb-gadget` creates a composite
  gadget with **NCM networking** (`usb0`, phone `172.16.42.1/24`, DHCP
  server via systemd-networkd) and **ACM serial** (`ttyGS0`, with a login
  prompt).
- **Host mode** (OTG adapter): keyboards, mice, USB disks, Ethernet adapters.
  The TUSB320L type-C controller switches roles and the PMI8994 provides VBUS.
- The port is USB 2.0 only on this phone (the USB3 PHY is not wired).

## Battery and charging

PMI8994 fuel gauge (`qcom_fg`) and charger (`qcom-smbchg`), from the
msm8996-mainline kernel. `upower -d`, `gemini-status`, or
`cat /sys/class/power_supply/*/capacity`.

`qcom-battery`'s `current_now` is positive while discharging. From a PC port
(`usb_type` `[SDP]`) the charger input stays at 500 mA; measured on a Mi 5
with sway, screen on and some CPU load, that loses ~0.5 A from the battery.
At 900 mA (`USB_PC_CURRENT=900`, the charger's USB 3.0 setting, applied by
`gemini-usb-current` from udev on every charger change) the same phone
charged at ~350 mA with the screen off. Wall chargers (DCP/CDP) get their
limit from the charger's own AICL.

## Audio

WCD9335 codec behind the ADSP (QDSP6, APR). Needs `adsp.mbn` (installed from
Android on first boot). UCM profiles for the Mi 5 (speaker, earpiece,
headphones, headset mic) are in `/usr/share/alsa/ucm2/Qualcomm/apq8096/xiaomi`.

```bash
alsaucm -c gemini list _verbs
speaker-test -c 2 -t wav
```

## GPU

Adreno 530 with Mesa freedreno (installed with the `sway`/`phosh` UIs or
`sudo apt install libgl1-mesa-dri mesa-vulkan-drivers`). Tested on a Mi 5:
freedreno FD530, OpenGL 3.1 / ES 3.2, Mesa 26.0. The msm driver probes from the
initramfs, before the root filesystem with the GPU firmware is mounted; it
loads `a530_pm4`/`a530_pfp`/`a530v3_gpmu` later, when the first program
opens `/dev/dri/renderD128`. The generic GPU
firmware comes from `linux-firmware-qualcomm-graphics`; the Xiaomi-signed
**zap shader** `a530_zap.mbn` is installed from Android on first boot. Without
it the display still works but there is no 3D acceleration.

## Modem

Q6V5 modem (`qcom_q6v5_mss`) with firmware from the `modem` partition,
`rmtfs` (modem file storage from the `modemst1/2`, `fsg` partitions) and
ModemManager over QRTR. Experimental: `mmcli -L`, `mmcli -m 0`.
To keep it off: uncomment `blacklist qcom_q6v5_mss` in
`/etc/modprobe.d/gemini.conf` and reboot.

## Sensors

Accelerometer, gyroscope, magnetometer, proximity and barometer sit behind the
sensor DSP (SLPI). It needs `slpi.mbn` and the sensor registry `sns.reg`, both
copied from Android on first boot (see [FIRMWARE.md](FIRMWARE.md)); the kernel
serves the registry to the DSP (`qcom_sns_reg`) and exposes the sensors as IIO
devices (`qcom_smgr`, `/sys/bus/iio/devices/`). They only deliver data through
the IIO buffer, so `cat in_*_raw` won't work:

```bash
sudo gemini-sensors        # one reading of every sensor (-w: keep printing)
```

The phosh UI installs `iio-sensor-proxy` for screen rotation.

## Clock

The PMIC real-time clock keeps running while the phone is off, but Linux can't
set it (Android keeps an offset in its own files instead). So
`gemini-rtc-offset.service` does the same: at boot the time is RTC + the offset
saved in `/var/lib/gemini/rtc-offset`, and the offset is saved again at
shutdown and every hour. NTP (`chrony`) corrects it once there is network. If
the battery ran completely flat the RTC restarts from zero; the clock then
continues from the last saved time until NTP fixes it. Set it by hand with
`sudo date -s '2026-10-31 12:00'` (saved within the hour or at shutdown).

## CPU speed

Two Kryo clusters: CPUs 0–1 ("small", up to 1.59 GHz) and 2–3 ("big", up to
2.15 GHz), clocked by `clk-cpu-8996`, with the frequency tables of
`msm8996.dtsi` and the speed bin from the fuses (`qcom-cpufreq-nvmem`). All
four share one supply, VDD_APCC (PM8994 S8–S11, set through the SAW).

Mainline has no CPR3 driver for MSM8996, so the OPPs had no voltages and the
clock was changed without touching the supply: going faster than the
bootloader's voltage allowed locked up the phone (`cpufreq.off=1` until now).
Kernel patch 0005 adds `cpu-supply` and per-OPP voltages taken from the
downstream (LineageOS) kernel's open-loop **ceilings**, which every chip must
run at (`msm8996-regulator.dtsi`, `qcom,cpr-voltage-ceiling`):

| | 905 mV | 1140 mV |
|---|---|---|
| small cores | 307 MHz – 1.23 GHz | 1.32 – 1.59 GHz |
| big cores | 307 MHz – 1.25 GHz | 1.32 – 2.15 GHz |

The lower downstream voltages (670/745 mV) aren't used: below 850 mV the CPU
memories must be moved to the MX rail (APM) and below 700 mV their timing
settings (MEM-ACC) must change, and mainline drives neither. So idle draws a
little more than Android, but nothing runs below a safe voltage. The CBF
(cluster interconnect) clock each OPP asks for stays inside the same corner.

The cpufreq drivers are modules (`qcom-cpufreq-nvmem`, `cpufreq-dt`) that
`gemini-cpufreq.service` loads after boot, then sets the `CPU_SPEED` limit and
the `schedutil` governor:

- `full`: every clock the chip's speed bin allows.
- `safe`: up to 1.23 / 1.25 GHz, all at 905 mV.
- `off`: drivers not loaded, the CPUs keep the bootloader's 1.04 GHz.

Guard: the level is saved as "being tested" before scaling starts, and
cleared after 10 minutes or at a clean shutdown. If a boot finds it still
set, the phone hung or restarted, and that boot uses one level lower until
you choose again with `cpu full|safe|off`. Thermal throttling uses the
cooling maps of `msm8996.dtsi`.

Check: `cpu`, `cat /sys/devices/system/cpu/cpufreq/policy*/stats/time_in_state`,
`cat /sys/kernel/debug/regulator/regulator_summary` (as root: VDD_APCC follows
the clock).

## Sleep

MSM8996 has no deep sleep (suspend to RAM) in mainline, and the PSCI cluster
idle states aren't described. What works is **suspend to idle** (s2idle):
programs are frozen, drivers suspended, and the CPUs wait in WFI until an
interrupt. It saves less than Android's sleep, but much more than staying
awake with WiFi and background programs running.

- `phone-sleep`: sleep now. `phone-sleep auto 10`: sleep after 10 minutes
  with the screen off, but not on a charger, not during an ssh login, and
  not while one of `SLEEP_BLOCKERS` runs (Claude Code, pi, apt...). Off by
  default: asleep, the phone is off the network.
- Wakes on: power key (then the screen comes on), volume up, Home, plugging in
  a charger, an RTC alarm (`sudo rtcwake -m freeze -s 600` sleeps 10 minutes).
- `/etc/systemd/sleep.conf.d/gemini.conf`: suspend = `freeze`; hibernation
  is off (no swap partition, and nothing to resume from).
- Guard: `gemini-sleep` writes `/var/lib/gemini/sleep-pending` before
  sleeping and removes it on waking. If a boot finds it, the last sleep never
  woke up, and automatic sleep is switched off. If a driver refuses to
  suspend, the phone simply stays awake, and automatic sleep waits 30 minutes
  before trying again (`journalctl -b | grep gemini-sleep`).

## Not supported

- **Deep sleep** (suspend to RAM, the whole SoC powered down): no mainline
  support for MSM8996. Use the s2idle sleep above, or keep it on a charger.
- **Cameras**, **fingerprint reader**, ambient light sensor (the DSP only
  reports proximity on this channel).
- Expect roughly 6–10 hours of battery with the screen off and WiFi on;
  keep it on a charger for 24/7 server use.
