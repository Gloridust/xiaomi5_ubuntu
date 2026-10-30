# Firmware

## Generic firmware (included)

From Ubuntu's `linux-firmware` packages, installed in the image:

| File | Used by |
|---|---|
| `ath10k/QCA6174/hw3.0/firmware-6.bin`, `board-2.bin` | WiFi |
| `qca/rampatch_00130302.bin`, `qca/nvm_00130302.bin` | Bluetooth |
| `qcom/a530_pm4.fw`, `qcom/a530_pfp.fw`, `qcom/a530v3_gpmu.fw2` | GPU |

## Device-specific firmware (from your phone)

These are signed with Xiaomi's key, so only the files from a Mi 5 work and
they can't be redistributed. The kernel expects them in
`/lib/firmware/qcom/msm8996/gemini/`:

| File | Used by | Found on Android in |
|---|---|---|
| `a530_zap.mbn` | GPU 3D acceleration | `system`: `/vendor/firmware/a530_zap.*` |
| `venus.mbn` | video decode/encode | `modem` or `system`: `venus.*` |
| `adsp.mbn` | audio | `modem` partition: `image/adsp.*` |
| `slpi.mbn` | sensor DSP | `modem` partition: `image/slpi_a1.*` (the stock gemini device tree's name; `slpi.*` also accepted) |
| `mba.mbn`, `modem.mbn` | modem | `modem` partition: `image/mba.mbn`, `image/modem.*` |

The sensor DSP also needs its **sensor registry** (calibration and sensor
list), which the kernel serves to it. It comes from the `persist` partition
(`sensors/sns.reg`) and is installed as
`/lib/firmware/qcom/sensors/sns.reg-xiaomi,gemini`.

Android stores most of them split into `name.mdt` + `name.b00`…`name.bNN`.
`gemini-firmware-install` joins them into one `.mbn` (same as
[pil-squasher](https://github.com/andersson/pil-squasher)).

### Option A – automatic (default)

At every boot `gemini-firmware.service` checks for missing files; if any are
missing it mounts the Android `modem`, `system`, `vendor` and `persist`
partitions read-only, installs what it finds and starts the DSPs (when
nothing is missing it exits at once). Re-run any time:

```bash
sudo gemini-firmware-install --force
cat /var/lib/gemini/firmware-installed     # what was found / missing
```

This needs the stock MIUI partitions to still be there (they are, unless you
wiped `system` from TWRP).

### Option B – bake into the image

With the phone in TWRP (or rooted Android) and adb:

```bash
scripts/extract-firmware.sh        # writes ./firmware/*.mbn
sudo ./build.sh                    # firmware/ is copied into the image
```

You can also drop files you got elsewhere (`.mbn`, or `.mdt` + `.bNN`) into
`./firmware/` before building.

### Option C – by hand on the phone

Copy the files to the phone, then:

```bash
sudo gemini-firmware-install --from ~/my-firmware-dir
sudo reboot
```
