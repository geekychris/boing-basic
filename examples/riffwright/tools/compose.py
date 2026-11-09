#!/usr/bin/env python3
"""Riffwright's demo songs, composed note by note here and written as ProTracker modules.

Everything is original: the tunes are written below, and every sample is synthesised
(no recordings), so the songs are free to redistribute (CC0, see demos/README).

    tools/compose.py [OUTDIR]      writes harbour_lights.mod and boing_shuffle.mod

Deterministic: the same files every time.
"""
import math, os, random, struct, sys

PAL = 3546895
NOTE = {n: i for i, n in enumerate(["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"])}
PER = [  # finetune 0, octaves 1..3
    856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
    428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
    214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113]


def per(name):
    """'A-2' → its period"""
    return PER[(int(name[2]) - 1) * 12 + NOTE[name[:2]]]


def s8(x):
    return max(-128, min(127, int(round(x)))) & 255


# ---------------------------------------------------------------- samples

def env(i, n, attack=8, decay=1.0):
    a = min(1.0, i / attack) if attack else 1.0
    return a * math.exp(-decay * i / n)


def kick(n=2400):
    out, ph = [], 0.0
    for i in range(n):
        f = 45 + 160 * math.exp(-i / 300)
        ph += 2 * math.pi * f / 16574
        out.append(s8(124 * math.sin(ph) * env(i, n, 4, 3.5)))
    return bytes(out)


def snare(n=2600, seed=7):
    r = random.Random(seed)
    out, ph, lp = [], 0.0, 0.0
    for i in range(n):
        ph += 2 * math.pi * 190 / 16574
        lp = 0.6 * lp + 0.4 * r.uniform(-1, 1)
        v = 70 * lp * env(i, n, 2, 4.5) + 55 * math.sin(ph) * env(i, n, 2, 9)
        out.append(s8(v * 1.4))
    return bytes(out)


def hat(n=700, seed=3):
    r = random.Random(seed)
    out, prev = [], 0.0
    for i in range(n):
        x = r.uniform(-1, 1)
        out.append(s8(90 * (x - prev) / 2 * env(i, n, 1, 6)))
        prev = x
    return bytes(out)


def additive(n, harmonics, cycles=1):
    """one looped wave of n samples: harmonics = [(k, amp)], `cycles` periods in the loop"""
    out = []
    peak = sum(abs(a) for _, a in harmonics)
    for i in range(n):
        v = sum(a * math.sin(2 * math.pi * k * cycles * i / n) for k, a in harmonics)
        out.append(s8(118 * v / peak))
    return bytes(out)


def bass(n=32):
    return additive(n, [(k, 1.0 / k * (0.85 ** k)) for k in range(1, 9)])


def lead(n=32):
    # a soft pulse: odd and some even harmonics
    return additive(n, [(1, 1.0), (2, 0.35), (3, 0.45), (4, 0.12), (5, 0.25), (7, 0.12)])


def pad(n=4096):
    # two detuned saws: 64 and 65 cycles in the loop, so it loops cleanly and beats slowly
    out = []
    for i in range(n):
        v = 0.0
        for cyc in (64, 65):
            for k in range(1, 7):
                v += math.sin(2 * math.pi * k * cyc * i / n) / k
        out.append(s8(40 * v))
    return bytes(out)


def bell(n=5000):
    out = []
    for i in range(n):
        t = i / 16574
        v = (math.sin(2 * math.pi * 523.25 * t) + 0.5 * math.sin(2 * math.pi * 523.25 * 2.76 * t) * math.exp(-t * 6)
             + 0.25 * math.sin(2 * math.pi * 523.25 * 5.4 * t) * math.exp(-t * 10))
        out.append(s8(70 * v * env(i, n, 6, 3.0)))
    return bytes(out)


# ---------------------------------------------------------------- the module

class Song:
    def __init__(self, title, npat):
        self.title = title
        self.samples = []
        self.cells = {}
        self.npat = npat

    def sample(self, name, data, vol=64, loop=None, fine=0):
        if len(data) % 2:
            data += b"\0"
        ls, ll = (0, 2) if loop is None else loop
        self.samples.append((name, data, fine, vol, ls, ll))
        return len(self.samples)

    def put(self, p, r, c, note=None, smp=0, fx=0, prm=0):
        pp = per(note) if note else 0
        old = self.cells.get((p, r, c))
        if old and note is None and smp == 0:
            pp, smp = old[0], old[1]
        self.cells[(p, r, c)] = (pp, smp, fx, prm)

    def write(self, path, orders, speed_tempo_first=True):
        out = bytearray(self.title.encode().ljust(20, b"\0")[:20])
        for i in range(31):
            if i < len(self.samples):
                name, data, fine, vol, ls, ll = self.samples[i]
            else:
                name, data, fine, vol, ls, ll = "", b"", 0, 0, 0, 2
            out += name.encode().ljust(22, b"\0")[:22]
            out += struct.pack(">HBBHH", len(data) // 2, fine, vol, ls // 2, ll // 2)
        out += bytes([len(orders), 127]) + bytes(orders + [0] * (128 - len(orders))) + b"M.K."
        for p in range(self.npat):
            for r in range(64):
                for c in range(4):
                    pp, smp, fx, prm = self.cells.get((p, r, c), (0, 0, 0, 0))
                    out += bytes([(smp & 0xF0) | (pp >> 8), pp & 255, ((smp & 15) << 4) | fx, prm])
        for s in self.samples:
            out += s[1]
        open(path, "wb").write(bytes(out))
        return len(out)


def harbour_lights(path):
    """A-minor, 125 BPM: drums, bass, arpeggiated pad chords, a lead with vibrato."""
    s = Song("Harbour Lights", 7)
    K = s.sample("kick (synth)", kick(), 64)
    S = s.sample("snare (synth)", snare(), 56)
    H = s.sample("hat (synth)", hat(), 40)
    B = s.sample("bass (synth)", bass(), 60, (0, 32))
    P = s.sample("pad (synth)", pad(), 34, (0, 4096))
    L = s.sample("lead (synth)", lead(), 50, (0, 32))
    E = s.sample("bell (synth)", bell(), 44)
    s.sample("Riffwright demo", b"", 0)
    s.sample("CC0 - free to use", b"", 0)

    chords = [("A-", 0x37), ("F-", 0x47), ("C-", 0x47), ("G-", 0x47)]   # Am F C G, arpeggio 0xy
    bassroots = ["A-1", "F-1", "C-2", "G-1"]

    def drums(p, fill=False, sparse=False):
        for r in range(64):
            if r % 16 in (0, 6, 10) and not (sparse and r % 16 == 6):
                s.put(p, r, 0, "C-2", K)
            elif r % 8 == 4:
                s.put(p, r, 0, "C-2", S)
            elif r % 2 == 0 and not sparse:
                s.put(p, r, 0, "F-3", H, 0xC, 0x20 if r % 4 else 0x30)
        if fill:
            for r in (58, 60, 61, 62, 63):
                s.put(p, r, 0, "C-2", S, 0xC, 0x20 + (r - 58) * 8)

    def bassline(p, busy=True):
        for bar in range(4):
            root = bassroots[bar]
            for r in (0, 3, 6, 8, 11, 14) if busy else (0, 8):
                note = root if r not in (6, 14) else root[:2] + str(int(root[2]) + 1)
                s.put(p, bar * 16 + r, 1, note, B)

    def padchords(p):
        for bar in range(4):
            name, arp = chords[bar]
            s.put(p, bar * 16, 2, name + "2", P, 0x0, arp)
            for r in range(1, 16):
                s.put(p, bar * 16 + r, 2, None, 0, 0x0, arp)

    def melody(p, line, ch=3, smp=None):
        smp = smp or L
        for r, note in line:
            if note == "off":
                s.put(p, r, ch, None, 0, 0xC, 0)
            elif note.startswith("~"):
                s.put(p, r, ch, None, 0, 0x4, int(note[1:], 16))
            else:
                s.put(p, r, ch, note, smp)

    # 0: intro, drums and bass; first instruction sets speed 6 / tempo 125
    drums(0, sparse=True)
    bassline(0, busy=False)
    for r in (0, 16, 32, 48):
        s.put(0, r, 2, "E-3", E)
    s.put(0, 0, 3, None, 0, 0xF, 6)
    s.put(0, 0, 2, None, 0, 0xF, 125)
    # 1: groove with chords
    drums(1)
    bassline(1)
    padchords(1)
    # 2/3: the tune
    tuneA = [(0, "E-3"), (4, "~44"), (8, "C-3"), (12, "D-3"), (16, "C-3"), (20, "A-2"), (24, "~34"),
             (30, "off"), (32, "F-2"), (36, "A-2"), (40, "C-3"), (44, "~44"), (48, "B-2"), (52, "G-2"),
             (56, "D-3"), (60, "~44")]
    tuneB = [(0, "E-3"), (2, "G-3"), (4, "A-3"), (8, "~46"), (14, "off"), (16, "G-3"), (18, "F-3"), (20, "E-3"),
             (24, "C-3"), (28, "~34"), (32, "D-3"), (36, "E-3"), (40, "F-3"), (44, "E-3"), (48, "D-3"),
             (52, "B-2"), (56, "G#2"), (60, "~46")]
    for p, tune in ((2, tuneA), (3, tuneB)):
        drums(p, fill=(p == 3))
        bassline(p)
        padchords(p)
        melody(p, tune)
    # 4: breakdown: pad and bells, the drums drop out, the bass holds
    padchords(4)
    bassline(4, busy=False)
    for r, n in ((0, "A-3"), (6, "E-3"), (12, "C-3"), (16, "A-3"), (22, "F-3"), (28, "C-3"),
                 (32, "G-3"), (38, "E-3"), (44, "C-3"), (48, "G-3"), (54, "D-3"), (60, "B-2")):
        s.put(4, r, 3, n, E)
    s.put(4, 48, 0, "C-2", K)
    for r in range(52, 64, 2):
        s.put(4, r, 0, "C-2", S, 0xC, 0x10 + (r - 52) * 4)
    # 5: the tune an octave up on the bell with the full groove
    drums(5)
    bassline(5)
    padchords(5)
    melody(5, [(r, n[:2] + str(min(3, int(n[2]) + 1)) if n[0] not in "o~" else n) for r, n in tuneA], 3, E)
    # 6: outro: the groove fades out (volume slides on every channel)
    drums(6, sparse=True)
    bassline(6, busy=False)
    padchords(6)
    for r in range(32, 64, 4):
        v = max(0, 0x30 - (r - 32) * 2)
        s.put(6, r, 1, None, 0, 0xC, v)
    s.put(6, 63, 3, None, 0, 0xF, 0)          # F00: stop (players treat it as the end)
    return s.write(path, [0, 1, 2, 3, 2, 3, 4, 1, 5, 3, 6])


def boing_shuffle(path):
    """A swung tune in D, 140 BPM, with portamento bass and a call-and-response lead."""
    s = Song("Boing Shuffle", 5)
    K = s.sample("kick (synth)", kick(2000), 64)
    S = s.sample("snare (synth)", snare(2400, 11), 52)
    H = s.sample("hat (synth)", hat(500, 5), 36)
    B = s.sample("bass (synth)", additive(32, [(1, 1), (2, .5), (3, .33), (4, .2)]), 60, (0, 32))
    L = s.sample("square lead (synth)", additive(32, [(k, 1.0 / k) for k in range(1, 12, 2)]), 44, (0, 32))
    O = s.sample("organ (synth)", additive(64, [(1, 1), (2, .6), (4, .4), (8, .2)], 2), 38, (0, 64))
    s.sample("Riffwright demo", b"", 0)
    s.sample("CC0 - free to use", b"", 0)
    swing = [0, 3, 4, 7, 8, 11, 12, 15]   # long-short pairs

    def groove(p, hats=True):
        for bar in range(4):
            b = bar * 16
            s.put(p, b, 0, "C-2", K)
            s.put(p, b + 8, 0, "C-2", K)
            s.put(p, b + 4, 0, "C-2", S)
            s.put(p, b + 12, 0, "C-2", S)
            if hats:
                for r in swing:
                    if (b + r) not in [(b + x) for x in (0, 4, 8, 12)]:
                        s.put(p, b + r, 0, "A-3", H, 0xC, 0x28)

    roots = ["D-1", "D-1", "G-1", "A-1"]

    def bass(p):
        for bar in range(4):
            r0 = roots[bar]
            up = r0[:2] + "2"
            seq = [(0, r0), (3, up), (4, r0), (7, up), (8, r0), (11, r0), (12, up), (15, r0)]
            for r, n in seq:
                s.put(p, bar * 16 + r, 1, n, B)
            s.put(p, bar * 16 + 14, 1, None, 0, 0x3, 0x20)   # tone portamento into the next bar

    def organ(p, chords):
        for bar, (n, arp) in enumerate(chords):
            for r in (0, 7, 8, 15):
                s.put(p, bar * 16 + r, 2, n, O, 0x0, arp)

    call = [(0, "D-3"), (3, "F#3"), (4, "A-3"), (8, "F#3"), (11, "E-3"), (12, "D-3")]
    resp = [(0, "A-2"), (3, "B-2"), (4, "D-3"), (7, "E-3"), (8, "D-3"), (12, "B-2")]
    chords = [("D-2", 0x47), ("D-2", 0x47), ("G-2", 0x47), ("A-2", 0x47)]
    # 0: intro, groove + bass, speed 5 tempo 140
    groove(0, hats=False)
    bass(0)
    s.put(0, 0, 3, None, 0, 0xF, 5)
    s.put(0, 0, 2, None, 0, 0xF, 140)
    # 1: + organ
    groove(1)
    bass(1)
    organ(1, chords)
    # 2/3: call and response
    for p, lines in ((2, (call, resp, call, resp)), (3, (resp, call, resp, [(0, "D-3"), (4, "~46")]))):
        groove(p)
        bass(p)
        organ(p, chords)
        for bar, line in enumerate(lines):
            for r, n in line:
                if n.startswith("~"):
                    s.put(p, bar * 16 + r, 3, None, 0, 0x4, int(n[1:], 16))
                else:
                    s.put(p, bar * 16 + r, 3, n, L)
    # 4: ending: one bar of hits, then stop
    for r in (0, 3, 4):
        s.put(4, r, 0, "C-2", K if r != 3 else S)
        s.put(4, r, 1, "D-1", B)
        s.put(4, r, 2, "D-2", O, 0x0, 0x47)
        s.put(4, r, 3, "D-3", L)
    s.put(4, 8, 3, None, 0, 0xF, 0)
    return s.write(path, [0, 1, 2, 3, 2, 3, 1, 2, 3, 4])


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "demos")
    os.makedirs(out, exist_ok=True)
    print("harbour_lights.mod", harbour_lights(os.path.join(out, "harbour_lights.mod")))
    print("boing_shuffle.mod", boing_shuffle(os.path.join(out, "boing_shuffle.mod")))
