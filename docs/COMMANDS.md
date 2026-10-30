# Easy commands on the phone

Type `phone-help` on the phone to see this list.

| Command | What it does |
|---|---|
| `menu` | menu with everything below (opens by itself after login on the phone screen) |
| `wifi` | connect to WiFi: pick a network from a list, type the password |
| `wifi status` | am I online, which network, which IP address |
| `wifi list` | networks in range |
| `wifi connect NAME PASSWORD` | connect directly |
| `wifi saved` / `wifi forget NAME` | remembered networks |
| `wifi fix` | WiFi stopped working: reset the driver and NetworkManager |
| `wifi hotspot` / `wifi hotspot off` | phone becomes a hotspot; join it and `ssh ubuntu@10.42.0.1` |
| `status` | battery, charger, temperatures, WiFi, IP, DSPs, firmware |
| `install-claude` | install / update Claude Code |
| `claude` / `claude-tmux` | start Claude Code (tmux version survives SSH drops) |
| `bright 40` | screen brightness 40 % |
| `screen-timeout 60` | screen off after 60 s without input (`0` = never) |
| `update` | update Ubuntu and the kernel |
| `sudo reboot` / `sudo poweroff` | restart / shut down |

## Buttons

| Button | Action |
|---|---|
| Power (short) | screen on / off |
| Power (hold 3 s) | power off |
| Volume up / down | arrow up / down (move in the menu) |
| Home (front button) | Enter (choose in the menu) |

The first press while the screen is off only wakes it up.

## On-screen keyboard

The keyboard at the bottom of the screen (buffyboard) types into the console.
It has Esc, Tab, Ctrl and Alt keys and a symbols layer; use the volume
keys as arrow up/down.

## Getting back in when WiFi is gone

1. Use the phone itself: `menu` → WiFi, or `wifi fix`.
2. USB cable to a PC: `ssh ubuntu@172.16.42.1` (always works, no WiFi needed).
3. Wait ~10 minutes: the phone starts the hotspot `Mi5-Ubuntu`; join it and
   `ssh ubuntu@10.42.0.1`. Password: `wifi status` on the phone, or
   `HOTSPOT_PASSWORD` in `/etc/default/gemini`.

## Settings file

`/etc/default/gemini`: screen timeout, button remapping, rescue hotspot
(`AUTO_HOTSPOT`, `HOTSPOT_SSID`, `HOTSPOT_PASSWORD`, `HOTSPOT_AFTER`), kernel
command line.
