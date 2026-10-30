# Troubleshooting

## The phone doesn't boot / stays on the Mi logo

1. Hold **Power + Volume Down** for ~10 s → fastboot.
2. Try a boot without changing anything: `scripts/flash.sh --try`.
3. Plug into a PC: if `ip link` on the PC shows a new USB network device or
   `/dev/ttyACM0` appears, Linux is running and only the display is the
   problem → `ssh ubuntu@172.16.42.1` and check `dmesg`.
4. Kernel log of the previous boot survives a reboot in RAM (ramoops). After
   rebooting into Ubuntu: `ls /sys/fs/pstore/`, `cat /sys/fs/pstore/console-ramoops*`.
5. If an update broke booting: in fastboot, flash the old image saved by
   `gemini-mkbootimg` (copy `/boot/boot.img.previous` off the phone first),
   or reflash the `boot.img` from your build.

## Dropped into an initramfs shell ("ALERT! LABEL=gemini-root does not exist")

The root filesystem wasn't found. Check that `rootfs.sparse.img` was flashed
to `userdata` (`fastboot flash userdata rootfs.sparse.img`). In the shell,
`ls /dev/disk/by-label/` and `cat /proc/partitions` show what the kernel sees.

## No on-screen keyboard

sway UI: press **volume up** (it may just be hidden). Otherwise, over SSH:
```bash
systemctl status gemini-sway       # the touch session on tty7
journalctl -b -u gemini-sway       # sway's errors
ls /dev/dri/card0                  # the session only starts when the display driver is up
```
Console UI:
```bash
systemctl status buffyboard        # should be running when /dev/fb0 exists
ls /dev/fb0 /dev/uinput
```
Plug in a USB OTG keyboard or use the USB serial/SSH console to investigate.

## Touch is offset / mirrored

Find the touchscreen and test it:
```bash
sudo libinput debug-events --show-keycodes      # touch the corners
```
If coordinates are scaled or flipped, add a calibration matrix, e.g. for a
flipped Y axis:
```bash
echo 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 -1 1"' |
	sudo tee /etc/udev/rules.d/91-touch-calibration.rules
sudo udevadm control --reload && sudo udevadm trigger
sudo systemctl restart gemini-sway   # console UI: sudo systemctl restart buffyboard
```

## WiFi missing

```bash
dmesg | grep -iE 'ath10k|pci'
ls /lib/firmware/ath10k/QCA6174/hw3.0/
nmcli radio wifi on; rfkill unblock all
```
If ath10k complains about the board file, copy Android's
`/vendor/firmware/bdwlan30.bin` (or `/system/etc/firmware/bdwlan30.bin`) to
`/lib/firmware/updates/ath10k/QCA6174/hw3.0/board.bin`, and move
`board-2.bin.zst` out of `/lib/firmware/ath10k/QCA6174/hw3.0/`, then reboot.

## Bluetooth controller "unconfigured"

`sudo systemctl start gemini-bt-mac@hci0`, then `bluetoothctl show`.

## No sound / no 3D / DSPs offline

```bash
gemini-status                           # look at "DSPs" and "Firmware"
cat /var/lib/gemini/firmware-installed
sudo gemini-firmware-install --force && sudo reboot
```

## Screen stays black after pressing power

The console screen is toggled by `gemini-powerkey`; check
`systemctl status gemini-powerkey`. Use the volume keys to wake as well.
Set `SCREEN_TIMEOUT=0` in `/etc/default/gemini` to keep the screen on.

## The phone hangs or restarts by itself a few minutes after booting

Most likely the CPU speed. Hold power for ~10 s to restart it: the next boot
notices and uses one level slower (`full` → `safe` → `off`); `cpu` shows the
level and why. If it still hangs, from TWRP's terminal (or after mounting the
Ubuntu partition) set `CPU_SPEED=off` in `/etc/default/gemini`. Please report
which level hung, with `journalctl -b -1 -u gemini-cpufreq` and
`/sys/fs/pstore/*` if there is anything.

## The phone doesn't wake up from sleep

Press power, then volume up or Home. If nothing helps, hold power ~10 s to
restart: automatic sleep is then switched off by itself. Find out what went
wrong with `journalctl -b -1 | tail -50` and `dmesg | grep -i -E 'suspend|resume'`.
If sleep fails at once ("could not sleep"), the kernel names the driver that
refused: `cat /sys/power/suspend_stats/last_failed_dev`.

## Change the kernel command line

Edit `KERNEL_CMDLINE` in `/etc/default/gemini`, then `sudo gemini-mkbootimg --flash`.
Useful extras: `loglevel=7` (more boot messages), `systemd.unit=rescue.target`.
