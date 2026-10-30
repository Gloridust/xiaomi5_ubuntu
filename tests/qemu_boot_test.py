#!/usr/bin/python3 -I
"""Drive a QEMU boot over the serial console: log in, change the forced
password, run checks, power off. Exit code 0 only if every check passed.
usage: qemu_boot_test.py Image.gz initrd disk.img console.log"""
import os, pty, re, select, sys, time

kernel, initrd, disk, logpath = sys.argv[1:5]
PW = "Gemini-Test-42"
cmd = ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a57", "-smp", "4", "-m", "2048",
       "-kernel", kernel, "-initrd", initrd,
       "-append", "root=LABEL=gemini-root rootwait ro console=ttyAMA0 loglevel=4",
       "-device", "qemu-xhci", "-drive", "if=none,id=d,format=raw,file=" + disk,
       "-device", "usb-storage,drive=d", "-netdev", "user,id=n",
       "-device", "virtio-net-pci,netdev=n", "-nographic", "-no-reboot"]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
log = open(logpath, "wb")
buf = b""
ANSI = re.compile(rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[A-Za-z]|\r")  # OSC (systemd shell integration), CSI, CR


def expect(pat, timeout):
    """Wait for regex pat; return the text before it."""
    global buf
    rx = re.compile(pat.encode())
    end = time.time() + timeout
    while time.time() < end:
        m = rx.search(buf)
        if m:
            before, buf = buf[:m.start()], buf[m.end():]
            return ANSI.sub(b"", before).decode(errors="replace")
        r, _, _ = select.select([fd], [], [], 1)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            log.write(data); log.flush(); buf += data
    raise TimeoutError(pat)


def send(s):
    os.write(fd, (s + "\r").encode())


PROMPT = r"\$ $"
fails = []
try:
    for pat, to, reply in [("login: ", 1800, "ubuntu"), ("Password: ", 120, "ubuntu"),
                           ("[Cc]urrent password: ", 120, "ubuntu"),
                           ("[Nn]ew password: ", 120, PW), ("[Rr]etype new password: ", 120, PW)]:
        expect(pat, to)
        send(reply)
    expect(PROMPT, 300)
    send("export SYSTEMD_PAGER=cat PAGER=cat"); expect(PROMPT, 60)

    def check(command, want, timeout=300):
        send(command)
        expect(re.escape(command), 60)
        out = expect(PROMPT, timeout).strip()
        ok = re.search(want, out, re.M) is not None
        print(("PASS " if ok else "FAIL ") + command + "\n     " + out.replace("\n", "\n     "))
        if not ok:
            fails.append(command)

    check("uname -r", r"-gemini")
    check("grep PRETTY /etc/os-release", r"Ubuntu 26\.04")
    check("findmnt -no OPTIONS /", r"^rw")
    check("findmnt -no LABEL /", r"gemini-root")
    # rmtfs/pd-mapper need Qualcomm hardware: allowed to fail in a VM
    check("systemctl --failed --no-legend --plain | grep -vE 'rmtfs|pd-mapper' | wc -l", r"^0$")
    check("systemctl is-active gemini-firstboot NetworkManager systemd-networkd ssh.socket | sort -u", r"^active$")
    check("ls /etc/ssh/ssh_host_*_key | wc -l", r"^[1-9]")
    check("swapon --show=NAME --noheadings", r"zram")
    check("aa-enabled", r"Yes")
    check("ls -l /boot/boot.img", r"boot\.img-")
    check("systemd-analyze", r"graphical\.target reached|multi-user\.target reached")
    # phone tools
    check("systemctl is-enabled gemini-wifi-watchdog.timer gemini-powerkey buffyboard | sort -u", r"^enabled$")
    check("sudo -n wifi status; echo rc=$?", r"No WiFi device")  # no WiFi chip in QEMU, but sudo works
    check("grep -c '^HOTSPOT_PASSWORD=' /etc/default/gemini", r"^1$")
    check("phone-help | head -2", r"easy commands")
    check("bash -n /usr/local/bin/menu && bash -n /usr/local/bin/wifi && echo syntax-ok", r"syntax-ok")
    check("for c in whiptail tmux git rg jq nmcli; do command -v $c >/dev/null || echo missing $c; done; echo tools-checked",
          r"^tools-checked$")
    check("echo %s | sudo -S -p '' /usr/local/sbin/gemini-wifi-watchdog; echo rc=$?" % PW, r"rc=0")
    if os.environ.get("QEMU_NET_TESTS") == "1":
        # Claude Code from Anthropic's official installer, on this image
        check("install-claude 2>&1 | tail -4", r"Done\. Start Claude Code", timeout=1500)
        check("~/.local/bin/claude --version", r"\d+\.\d+\.\d+", timeout=600)
    send("echo %s | sudo -S -p '' poweroff" % PW)
    expect("Power down|reboot: ", 600)
except TimeoutError as e:
    fails.append("timeout waiting for %s" % e)
finally:
    try:
        os.kill(pid, 9)
    except OSError:
        pass

print("QEMU boot test: %s" % ("PASSED" if not fails else "FAILED: " + "; ".join(fails)))
sys.exit(1 if fails else 0)
