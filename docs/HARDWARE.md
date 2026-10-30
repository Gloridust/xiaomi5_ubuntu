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
| `console` (default) | **buffyboard** | draws on the framebuffer, sends keys to the active console through `uinput`, and shrinks the console so text isn't hidden. Config: `/etc/buffyboard.conf.d/gemini.conf` (theme, layout). |
| `sway` | **wvkbd-mobintl** | Wayland layer-shell keyboard. **Volume up** shows/hides it, **volume down** opens a new terminal. Config: `/usr/local/share/gemini/sway/config`. |
| `phosh` | **squeekboard** | appears automatically in text fields. |

Switch an installed console system to the sway GUI:

```bash
sudo apt install sway swayidle swaylock foot wvkbd i3status fonts-dejavu-core libgl1-mesa-dri
sudo cp /path/to/repo/rootfs-overlay/etc/systemd/system/gemini-sway.service /etc/systemd/system/
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

Check: `iw dev`, `dmesg | grep ath10k`.

## Bluetooth

Same QCA6174 chip, over UART (`hci_uart` with the QCA protocol). Firmware
`qca/rampatch_00130302.bin` + `qca/nvm_00130302.bin` from linux-firmware.
The chip has no MAC address of its own under Linux, so `gemini-bt-mac@hci0`
sets a stable one derived from the phone's serial number.

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
`sudo apt install libgl1-mesa-dri mesa-vulkan-drivers`). The generic GPU
firmware comes from `linux-firmware-qualcomm-graphics`; the Xiaomi-signed
**zap shader** `a530_zap.mbn` is installed from Android on first boot. Without
it the display still works but there is no 3D acceleration.

## Modem

Q6V5 modem (`qcom_q6v5_mss`) with firmware from the `modem` partition,
`rmtfs` (modem file storage from the `modemst1/2`, `fsg` partitions) and
ModemManager over QRTR. Experimental: `mmcli -L`, `mmcli -m 0`.
To keep it off: uncomment `blacklist qcom_q6v5_mss` in
`/etc/modprobe.d/gemini.conf` and reboot.

## Not supported

- **Suspend**: MSM8996 deep sleep isn't supported upstream. The phone stays
  awake (good for a server); the screen turns off. Sleep targets are masked.
- **Sensors** (SLPI DSP needs `sns.reg` + hexagonrpcd setup), **cameras**,
  **fingerprint reader**.
- Expect roughly 6–10 hours of battery with the screen off and WiFi on;
  keep it on a charger for 24/7 server use.
