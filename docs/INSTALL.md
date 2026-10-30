# Installing Ubuntu 26.04 on the Xiaomi Mi 5

> ⚠️ This replaces Android's **boot** and **userdata** partitions. All apps,
> photos and files on the phone are erased. `system`, `vendor`, `modem`,
> `persist` and the bootloader are **not** touched, so you can always go back
> by flashing a MIUI fastboot ROM.

## 1. Unlock the bootloader (once)

1. In MIUI: *Settings → About phone →* tap *MIUI version* 7× to enable
   developer options. In *Developer options* enable **OEM unlocking** and
   **Mi Unlock status** (bind your Mi account).
2. Power off, hold **Power + Volume Down** → fastboot screen.
3. On a Windows PC run Xiaomi's **Mi Unlock** tool, sign in, press *Unlock*.
   (There can be a waiting period imposed by Xiaomi.)
4. Check: `fastboot getvar unlocked` should print `unlocked: yes`.

Recommended: be on the latest official MIUI first (MIUI 10, Android 8.0).
Ubuntu uses the firmware that MIUI installed in the `modem` and `system`
partitions.

## 2. Get the images

**Build them** on an Ubuntu 24.04 or newer PC (x86_64 or arm64; about 20 GB
of disk and 1–2 hours on 4 cores):

```bash
git clone <this repository>
cd xiaomi5_ubuntu
sudo ./build.sh
```

Options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `UI` | `console` | `console` = text console + buffyboard keyboard; `sway` = touch GUI with terminal + wvkbd keyboard; `phosh` = phone shell + squeekboard |
| `WIFI_SSID`, `WIFI_PASSWORD` | – | connect to this WiFi automatically |
| `SSH_AUTHORIZED_KEYS` | – | file with SSH public keys for the `ubuntu` user |
| `DEFAULT_USER`, `DEFAULT_PASSWORD` | `ubuntu` / `ubuntu` | first login (password must be changed) |
| `EXTRA_PACKAGES` | – | more Ubuntu packages, e.g. `"docker.io nginx"` |
| `KERNEL_CMDLINE` | see `config/device.conf` | kernel arguments |

Example: `sudo UI=sway WIFI_SSID=home WIFI_PASSWORD=secret ./build.sh`

Output in `out/`: `boot.img`, `rootfs.sparse.img`, `linux-image-*.deb`.

**Or download them** from this repository's GitHub Actions ("Build Mi 5 Ubuntu
images" → *Run workflow*, then download the artifact) or a release.

## 3. Flash

Phone in fastboot mode (**Power + Volume Down**), USB connected:

```bash
scripts/flash.sh                    # images in ./out
IMAGES_DIR=~/Downloads scripts/flash.sh
```

The script checks that the phone really is a Mi 5 (`product: gemini`) and is
unlocked, then runs:

```bash
fastboot flash boot boot.img
fastboot flash userdata rootfs.sparse.img
fastboot reboot
```

Windows: install the Android platform tools and run those three commands.

## 4. First boot

The first boot takes about a minute longer. The phone:

1. grows the filesystem to fill `userdata` (~24 GB on a 32 GB phone),
2. creates its own SSH host keys,
3. copies the signed GPU/DSP/modem firmware from the Android partitions and
   starts the DSPs (`gemini-firmware-install`).

Then the login prompt appears with the **on-screen keyboard** at the bottom.

- Log in as **ubuntu**, password **ubuntu**, then choose a new password.
- **Power key (short)**: screen off/on. The screen also turns off after 2
  minutes without input (`SCREEN_TIMEOUT` in `/etc/default/gemini`).
- **Power key (hold 3 s)**: power off.

## 5. Connect to WiFi

```bash
sudo nmtui                               # menu: "Activate a connection"
# or
sudo nmcli dev wifi list
sudo nmcli dev wifi connect "MyWiFi" password "secret"
```

NetworkManager remembers the network and reconnects after reboots.

## 6. Use it from a PC (USB)

Connect the phone to a PC with a USB cable. The phone appears as a USB network
adapter **and** a USB serial port:

```bash
ssh ubuntu@172.16.42.1                 # PC gets 172.16.42.x by DHCP
screen /dev/ttyACM0 115200             # serial login console (Linux/macOS)
```

On Windows the network adapter appears as "UsbNcm Host Device" (Windows 10
2004 and newer have the driver built in); the serial console is a COM port.

To share the PC's internet with the phone over USB, enable connection
sharing/NAT on the PC for that interface and on the phone run
`sudo ip route add default via 172.16.42.<PC address>`.

## 7. Updating

```bash
sudo apt update && sudo apt full-upgrade
```

Ubuntu packages update from the official Ubuntu archive. The kernel is this
project's `linux-image-*-gemini` package; install a newer build with
`sudo apt install ./linux-image-...deb`. After any kernel or initramfs change
`gemini-mkbootimg` automatically rebuilds `/boot/boot.img` and writes it to
the boot partition. The previous image is saved as `/boot/boot.img.previous`.

## 8. Going back to Android

Flash an official MIUI **fastboot ROM** for `gemini` with Xiaomi's MiFlash (or
its `flash_all.sh`), choosing *clean all* (do not choose *clean all and lock*
unless you want a locked bootloader).
