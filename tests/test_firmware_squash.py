#!/usr/bin/python3 -I
"""Check gemini-firmware-install joins split .mdt/.bNN firmware correctly.

Builds a fake Qualcomm-style ELF32 and ELF64 image, splits it the way Android
stores it (foo.mdt = headers + hash segment, foo.bNN = one file per segment),
runs the installer and compares the result with the original.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "rootfs-overlay", "usr", "local", "sbin", "gemini-firmware-install")


def make_elf(cls64, segments):
    """segments: list of (offset, bytes). Returns full image bytes."""
    phnum = len(segments)
    if cls64:
        ehsize, phentsize, phoff = 64, 56, 64
        hdr = bytearray(b"\x7fELF" + bytes([2, 1, 1]) + bytes(9))
        hdr += struct.pack("<HHIQQQIHHHHHH", 2, 164, 1, 0, phoff, 0, 0, ehsize, phentsize, phnum, 0, 0, 0)
    else:
        ehsize, phentsize, phoff = 52, 32, 52
        hdr = bytearray(b"\x7fELF" + bytes([1, 1, 1]) + bytes(9))
        hdr += struct.pack("<HHIIIIIHHHHHH", 2, 164, 1, 0, phoff, 0, 0, ehsize, phentsize, phnum, 0, 0, 0)
    for off, data in segments:
        if cls64:
            hdr += struct.pack("<IIQQQQQQ", 1, 7, off, 0, 0, len(data), len(data), 0x1000)
        else:
            hdr += struct.pack("<8I", 1, off, 0, 0, len(data), len(data), 7, 0x1000)
    size = max(off + len(d) for off, d in segments)
    img = bytearray(size)
    for off, data in segments:
        img[off:off + len(data)] = data
    img[0:len(hdr)] = hdr
    return bytes(img), len(hdr)


def run_case(cls64, tmp):
    rnd = random.Random(42 + cls64)
    hash_seg = bytes(rnd.getrandbits(8) for _ in range(0x200))
    code = bytes(rnd.getrandbits(8) for _ in range(0x5000))
    data = bytes(rnd.getrandbits(8) for _ in range(0x1800))
    # segment 0 = ELF headers (filled in by make_elf), 1 = hash, 2-3 = payload,
    # 4 = empty (bss-like, filesz 0 is skipped by the tool)
    segs = [(0, bytes(0x100)), (0x1000, hash_seg), (0x2000, code), (0x8000, data)]
    full, hlen = make_elf(cls64, segs)
    # put real header bytes into segment 0 for the split files
    segs[0] = (0, full[:0x100])

    src = os.path.join(tmp, "src%d" % cls64)
    os.makedirs(src)
    # Android-style .mdt: headers + hash segment, payload only in .bNN
    with open(os.path.join(src, "adsp.mdt"), "wb") as f:
        f.write(full[:0x1000 + len(hash_seg)])
    for i, (off, d) in enumerate(segs):
        with open(os.path.join(src, "adsp.b%02d" % i), "wb") as f:
            f.write(d)
    # an already-joined file is copied as is; upper case names are found too
    with open(os.path.join(src, "MBA.MBN"), "wb") as f:
        f.write(b"mba-content")

    dst = os.path.join(tmp, "dst%d" % cls64)
    subprocess.run([sys.executable, "-I", TOOL, "--from", src, "--dest", dst],
                   check=True, stdout=subprocess.DEVNULL)
    with open(os.path.join(dst, "adsp.mbn"), "rb") as f:
        out = f.read()
    assert out == full, "squashed image differs (ELF%d)" % (64 if cls64 else 32)
    with open(os.path.join(dst, "mba.mbn"), "rb") as f:
        assert f.read() == b"mba-content"
    assert not os.path.exists(os.path.join(dst, "modem.mbn"))


def main():
    with tempfile.TemporaryDirectory() as tmp:
        run_case(False, tmp)
        run_case(True, tmp)
    print("firmware squash tests passed")


if __name__ == "__main__":
    main()
