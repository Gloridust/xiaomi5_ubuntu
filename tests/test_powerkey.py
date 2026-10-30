#!/usr/bin/python3 -I
"""Simulate the Mi 5 buttons and check gemini-powerkey's behaviour:
short power press toggles the screen, volume/home are sent as up/down/Enter,
a press on a dark screen only wakes it, touch is grabbed while dark."""
import importlib.machinery, importlib.util, os, select, signal, sys, types

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "rootfs-overlay", "usr", "local", "sbin", "gemini-powerkey")

# --- fake evdev -------------------------------------------------------------
ec = types.SimpleNamespace(EV_KEY=1, EV_ABS=3, KEY_POWER=116, KEY_VOLUMEUP=115,
                           KEY_VOLUMEDOWN=114, KEY_HOME=102, KEY_UP=103, KEY_DOWN=108,
                           KEY_ENTER=28, BTN_TOUCH=330)
Ev = lambda t, c, v: types.SimpleNamespace(type=t, code=c, value=v)


class Dev:
    def __init__(self, fd, caps):
        self.fd, self._caps, self.queue, self.grabbed = fd, caps, [], False
    def capabilities(self): return self._caps
    def read(self):
        q, self.queue = self.queue, []
        return q
    def grab(self): self.grabbed = True
    def ungrab(self): self.grabbed = False


pwr = Dev(10, {ec.EV_KEY: [ec.KEY_POWER]})
gpio = Dev(11, {ec.EV_KEY: [ec.KEY_VOLUMEUP, ec.KEY_HOME]})
resin = Dev(12, {ec.EV_KEY: [ec.KEY_VOLUMEDOWN]})
touch = Dev(13, {ec.EV_KEY: [ec.BTN_TOUCH], ec.EV_ABS: [0, 1]})
DEVS = {"/dev/input/event%d" % d.fd: d for d in (pwr, gpio, resin, touch)}
sent = []


class UInput:
    def __init__(self, caps, name=None): pass
    def write(self, t, c, v): sent.append((c, v))
    def syn(self): pass


evdev = types.ModuleType("evdev")
evdev.ecodes = ec
evdev.UInput = UInput
evdev.list_devices = lambda: list(DEVS)
evdev.InputDevice = lambda p: DEVS[p]
sys.modules["evdev"] = evdev

loader = importlib.machinery.SourceFileLoader("powerkey", TOOL)
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("powerkey", loader))
loader.exec_module(mod)
mod.read_conf = lambda: {"SCREEN_TIMEOUT": "0"}
states = []
mod.Screen.set = lambda self, on: (states.append(on), setattr(self, "on", on))

# --- scripted input -----------------------------------------------------------
script = [
    (gpio, [Ev(1, ec.KEY_VOLUMEUP, 1), Ev(1, ec.KEY_VOLUMEUP, 0)]),   # -> UP
    (resin, [Ev(1, ec.KEY_VOLUMEDOWN, 1), Ev(1, ec.KEY_VOLUMEDOWN, 0)]),  # -> DOWN
    (gpio, [Ev(1, ec.KEY_HOME, 1), Ev(1, ec.KEY_HOME, 0)]),           # -> ENTER
    (pwr, [Ev(1, ec.KEY_POWER, 1), Ev(1, ec.KEY_POWER, 0)]),          # screen off
    (gpio, [Ev(1, ec.KEY_HOME, 1), Ev(1, ec.KEY_HOME, 0)]),           # wake only
    (gpio, [Ev(1, ec.KEY_VOLUMEUP, 1), Ev(1, ec.KEY_VOLUMEUP, 0)]),   # -> UP
    "SIGUSR1",                                                        # phone-sleep: off
]
step = {"i": 0}
grab_seen = []


def fake_select(r, w, x, t=None):
    grab_seen.append(touch.grabbed)
    if step["i"] >= len(script):
        raise SystemExit(0)
    entry = script[step["i"]]
    step["i"] += 1
    if entry == "SIGUSR1":
        os.kill(os.getpid(), signal.SIGUSR1)
        return [], [], []
    d, evs = entry
    d.queue = evs
    return [d.fd], [], []


mod.select.select = fake_select
try:
    mod.main()
except SystemExit:
    pass

U, D, E = ec.KEY_UP, ec.KEY_DOWN, ec.KEY_ENTER
want = [(U, 1), (U, 0), (D, 1), (D, 0), (E, 1), (E, 0), (U, 1), (U, 0)]
assert sent == want, "remapped keys: %r" % sent
# on at start (from a known state), off with the power key, on again on
# wake, off on SIGUSR1 (phone-sleep)
assert states == [True, False, True, False], "screen states: %r" % states
assert gpio.grabbed and resin.grabbed and not pwr.grabbed, "button devices must be grabbed"
assert True in grab_seen, "touchscreen should be grabbed while the screen is off"
assert grab_seen[-2] is False, "touchscreen released after waking"
assert touch.grabbed, "touchscreen grabbed again after SIGUSR1"
print("powerkey test passed")
