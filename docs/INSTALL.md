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
| `UI` | `sway` | `sway` = touch GUI with terminal + wvkbd keyboard (GPU-rendered); `console` = text console + buffyboard keyboard (least RAM); `phosh` = phone shell + squeekboard |
| `WIFI_SSID`, `WIFI_PASSWORD` | – | connect to this WiFi automatically |
| `SSH_AUTHORIZED_KEYS` | – | file with SSH public keys for the `ubuntu` user |
| `DEFAULT_USER`, `DEFAULT_PASSWORD` | `ubuntu` / `ubuntu` | first login (password must be changed) |
| `EXTRA_PACKAGES` | – | more Ubuntu packages, e.g. `"docker.io nginx"` |
| `KERNEL_CMDLINE` | see `config/device.conf` | kernel arguments |

Example: `sudo UI=console WIFI_SSID=home WIFI_PASSWORD=secret ./build.sh`

Output in `out/`: `boot.img`, `rootfs.sparse.img`, `linux-image-*.deb`.

**Or download them** from this repository's GitHub Actions: open *Actions →
Build Mi 5 Ubuntu images*, pick a successful run (or *Run workflow*, choosing
the UI), and download the `xiaomi-gemini-ubuntu-26.04-<ui>` artifact. Unzip it;
it contains `boot.img`, `rootfs.sparse.img.xz`, the kernel `.deb` and
`SHA256SUMS`. Artifacts are kept for 30 days; push a `v*` tag to publish a
permanent release instead.

## 3. Install

### With TWRP (easiest if you already have TWRP)

1. Download `ubuntu-26.04-xiaomi-gemini-twrp.zip` from the latest
   [release](https://github.com/Gloridust/xiaomi5_ubuntu/releases/latest) (or build it: `sudo scripts/40-make-twrp-zip.sh`).
2. Get it to the phone in one of these ways:
   - **adb sideload** (recommended): TWRP → Advanced → ADB Sideload → swipe, then on the PC
     `adb sideload ubuntu-26.04-xiaomi-gemini-twrp.zip`
   - a **USB OTG drive**: TWRP → Install → Select Storage → USB-OTG
   - internal storage also works: the installer first copies the zip into RAM,
     because internal storage is erased during the install
3. TWRP → Install → the zip → swipe. It:
   - checks the phone is a Mi 5,
   - saves the GPU/audio/modem firmware from your current system (works with
     custom ROMs too) into Ubuntu,
   - keeps a copy of the current boot image (`/var/lib/gemini/android-boot.img`),
   - writes Ubuntu to userdata and the Ubuntu boot image to boot.
4. Reboot System.

### With fastboot

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

Then a terminal opens with the **on-screen keyboard** at the bottom and the
list of easy commands (`phone-help`).

- No login on the phone's own screen. The first `sudo` (and the first SSH
  login) asks for the password **ubuntu** and makes you choose a new one.
- **Volume up**: show/hide the keyboard. **Volume down**: another terminal
  (tap the titles at the top to switch).
- Console builds (`UI=console`): log in as **ubuntu** / **ubuntu** instead.
- **Power key (short)**: screen off/on. The screen also turns off after 2
  minutes without input (`SCREEN_TIMEOUT` in `/etc/default/gemini`).
- **Power key (hold 3 s)**: power off.

## 5. Connect to WiFi

After login the **menu** opens on the phone's screen: *WiFi → Connect to a
network*, pick yours, type the password. Or on the command line:

```bash
wifi                                     # pick from a list, asks for the password
wifi connect "MyWiFi" "secret"
wifi status                              # connected? IP address?
```

The phone remembers the network and reconnects by itself. If WiFi is lost,
a watchdog retries every 2 minutes, resets the WiFi driver after 3 failures,
and after about 10 minutes starts a **rescue hotspot** called `Mi5-Ubuntu`:
join it from a laptop or another phone and `ssh ubuntu@10.42.0.1`. Its
password is shown by `wifi status` (and stored in `/etc/default/gemini`).
`wifi fix` resets the WiFi by hand.

## 5b. Claude Code

```bash
install-claude      # Anthropic's official installer (needs internet)
claude              # start it
claude-tmux         # same, but keeps running if your SSH connection drops
```

Or from the menu: *Claude Code*. Log in with your Claude account when it asks.
The phone has 3 GB RAM plus compressed swap; Claude Code runs fine in the text
console or over SSH.

## 5c. pi agent (DeepSeek)

```bash
install-pi          # installs Node.js from Ubuntu and pi, then asks for a DeepSeek API key
pi                  # start it (DeepSeek is the default model)
pi-tmux             # same, but keeps running if your SSH connection drops
pi update           # update pi later
```

Or from the menu: *AI agents*. Get a key at https://platform.deepseek.com/api_keys;
it is stored in `~/.pi/agent/auth.json`, readable only by you. `install-pi` does
not run a downloaded script: it installs the exact package versions pinned in
`/usr/local/share/gemini/pi/package-lock.json` with `npm ci`. The first start
takes about 12 s while Node compiles pi, later starts about 4 s.

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
