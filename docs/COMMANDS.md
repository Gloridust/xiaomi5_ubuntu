# Easy commands on the phone

Type `phone-help` on the phone to see this list.

| Command | What it does |
|---|---|
| `menu` | menu with everything below (console UI: opens by itself after login on the phone screen) |
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
| `install-pi` | install the pi coding agent and enter a DeepSeek API key (run again to change the key) |
| `pi` / `pi-tmux` | start pi (tmux version survives SSH drops); `pi update` updates it |
| `bright 40` | screen brightness 40 % |
| `screen-timeout 60` | screen off after 60 s without input (`0` = never) |
| `update` | update Ubuntu and the kernel |
| `sudo reboot` / `sudo poweroff` | restart / shut down |

## Buttons

| Button | sway UI (default) | console UI |
|---|---|---|
| Power (short) | screen on / off | screen on / off |
| Power (hold 3 s) | power off | power off |
| Volume up | show / hide the keyboard | arrow up (move in the menu) |
| Volume down | open another terminal | arrow down |
| Home (front button) | – | Enter (choose in the menu) |

Console UI: the first press while the screen is off only wakes it up.

## On-screen keyboard

**sway UI** (wvkbd): Esc, Tab, arrow keys and `Ctr` (Ctrl) are on the top row.
`Ctr` is sticky: tap `Ctr`, then `c` for Ctrl+C. The bottom-left key switches
to numbers and symbols; `Cmp` types accented letters. Drag a finger up/down
over the terminal to scroll back; tap the titles at the top to switch
terminals. The status bar shows CPU, RAM, GPU clock, WiFi (name and signal),
battery (`CHG` = charging, `BAT` = on battery) and the time.

**console UI** (buffyboard): types into the console. It has Esc, Tab, Ctrl and
Alt keys and a symbols layer; use the volume keys as arrow up/down.

## Getting back in when WiFi is gone

1. Use the phone itself: `menu` → WiFi, or `wifi fix`.
2. USB cable to a PC: `ssh ubuntu@172.16.42.1` (always works, no WiFi needed).
3. Wait ~10 minutes: the phone starts the hotspot `Mi5-Ubuntu`; join it and
   `ssh ubuntu@10.42.0.1`. Password: `wifi status` on the phone, or
   `HOTSPOT_PASSWORD` in `/etc/default/gemini`.

## Settings file

`/etc/default/gemini`: screen timeout, button remapping, rescue hotspot
(`AUTO_HOTSPOT`, `HOTSPOT_SSID`, `HOTSPOT_PASSWORD`, `HOTSPOT_AFTER`), charging
from a PC (`USB_PC_CURRENT`), kernel command line.

**Charging from a PC loses charge?** A PC's USB port gives 500 mA, less than the
phone uses with the screen on. On a USB 3.0 port (usually blue) set
`USB_PC_CURRENT=900` in `/etc/default/gemini`, then `sudo gemini-usb-current`
(or replug). Not on USB 2.0 ports: they may switch off. A wall charger is better.
