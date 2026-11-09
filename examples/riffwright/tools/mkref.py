#!/usr/bin/env python3
"""Write the reference .mod files for Riffwright's round-trip tests (tests/ref/).

An independent writer of the ProTracker layout, so the BASIC loader/saver is checked
against bytes it did not produce. Deterministic: run it again and the files are the same.
"""
import math, os, random, struct, sys

def mod(title, tag, nch, npat, samples, orders, songlen, restart, cells, tail=b""):
    out = bytearray()
    out += title.ljust(20, b"\0")[:20]
    for i in range(31):
        if i < len(samples):
            name, data, fine, vol, ls, ll = samples[i]
        else:
            name, data, fine, vol, ls, ll = b"", b"", 0, 0, 0, 2
        out += name.ljust(22, b"\0")[:22]
        out += struct.pack(">HBBHH", len(data) // 2, fine, vol, ls // 2, ll // 2)
    out += bytes([songlen, restart])
    out += bytes(orders + [0] * (128 - len(orders)))
    out += tag
    for p in range(npat):
        for r in range(64):
            for c in range(nch):
                per, smp, fx, prm = cells.get((p, r, c), (0, 0, 0, 0))
                out += bytes([(smp & 0xF0) | (per >> 8), per & 255, ((smp & 15) << 4) | fx, prm])
    for s in samples:
        out += s[1]
    return bytes(out + tail)

def wave(n, f):
    return bytes([(int(f(i)) & 255) for i in range(n)])

def main(outdir):
    rnd = random.Random(1987)
    sine = wave(64, lambda i: 100 * math.sin(i * 2 * math.pi / 64))
    saw = wave(512, lambda i: (i % 128) * 2 - 128)
    noise = bytes(rnd.randrange(256) for _ in range(2000))
    smps = [
        (b"sine loop", sine, 0, 64, 0, 64),
        (b"saw", saw, 3, 48, 128, 256),
        (b"noise\0junk", noise, 13, 40, 0, 2),          # finetune -3, no loop, junk after NUL
    ]
    smps += [(b"", b"", 0, 0, 0, 2)] * 13
    smps.append((b"high number", wave(100, lambda i: i), 0x25, 33, 0, 2))  # sample 17, raw hi nibble
    cells = {}
    periods = [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453, 428, 431, 214, 113, 57, 1712]
    for p in range(3):
        for r in range(0, 64, 2):
            c = (r // 2 + p) % 4
            per = periods[(r + p) % len(periods)]
            cells[(p, r, c)] = (per, [1, 2, 3, 17][(r // 4) % 4], (r // 2) % 16, (r * 7 + p) & 255)
    cells[(2, 63, 3)] = (0, 0, 0xD, 0)
    m = mod(b"riffwright ref\0xyz", b"M.K.", 4, 3, smps, [0, 1, 2, 1, 0], 5, 127, cells, b"TAILDATA")
    open(os.path.join(outdir, "ref4.mod"), "wb").write(m)
    # 6 and 8 channels
    for nch, tag in ((6, b"6CHN"), (8, b"8CHN")):
        cells = {}
        for r in range(64):
            for c in range(nch):
                if (r + c) % 3 == 0:
                    cells[(0, r, c)] = (periods[(r * c) % len(periods)], 1 + c % 2, 0xC, r)
        m = mod(b"%d channels" % nch, tag, nch, 1, smps[:2], [0], 1, 0, cells)
        open(os.path.join(outdir, "ref%d.mod" % nch), "wb").write(m)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "tests", "ref"))
