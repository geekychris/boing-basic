#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Glimmerfield's music: "Glimmer Drift", an original tune in A minor (written for the game,
2026-11-08; every sample synthesised by modlib.py, no recorded sound).

Lead bell on channel 0, bass on 1, drums on 2, a shimmering arpeggio pad on 3.
Writes examples/glimmerfield/glimmer.mod.
"""
import os
from modlib import Song, m, cycle, pluck, pad, kick, snare, hat, MINOR, MAJOR

here = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(here, "..", "..", "examples", "glimmerfield", "glimmer.mod")

song = Song("glimmer drift", speed=6, bpm=118)
bell = song.instrument("bell", pluck("bell", 32, cycles=48, sustain=0.3, amp=110), 44)
bass = song.instrument("bass", pluck("triangle", 64, cycles=24, sustain=0.45, amp=120), 58)
shim = song.instrument("shimmer", pad("square", 32, beats=16, amp=60, detune=1, duty=0.3), 20)
bd = song.instrument("kick", kick(ms=160), 56)
sd = song.instrument("snare", snare(ms=130), 34)
hh = song.instrument("hat", hat(ms=35, amp=60), 24)
glass = song.instrument("glass", pluck("sine", 16, cycles=40, sustain=0, amp=100), 34)

Am, F, C, G = ("A-1", "A-2", MINOR), ("F-1", "F-2", MAJOR), ("C-1", "C-2", MAJOR), ("G-1", "G-2", MAJOR)
Dm, E = ("D-1", "D-2", MINOR), ("E-1", "E-2", MAJOR)

MEL = {
    "a": m("E-3:4 C-3:2 A-2:2 B-2:4 C-3:4 "
           "A-2:4 F-2:2 A-2:2 C-3:6 .:2 "
           "G-2:4 C-3:2 E-3:2 D-3:4 C-3:4 "
           "B-2:4 D-3:2 G-2:2 B-2:6 .:2"),
    "a2": m("E-3:4 A-3:2 G-3:2 E-3:4 C-3:4 "
            "F-3:4 E-3:2 C-3:2 A-2:6 .:2 "
            "D-3:4 F-3:2 E-3:2 D-3:4 A-2:4 "
            "B-2:4 G#2:2 B-2:2 E-3:8"),
    "b": m("A-2:2 C-3:2 E-3:2 A-3:2 G-3:4 E-3:4 "
           "F-3:2 E-3:2 C-3:4 A-2:8 "
           "C-3:2 E-3:2 G-3:2 C-3:2 B-2:4 G-2:4 "
           "A-2:2 B-2:2 C-3:2 D-3:2 E-3:8"),
    "b2": m("A-3:4 G-3:2 E-3:2 C-3:4 E-3:4 "
            "F-3:4 A-3:2 F-3:2 C-3:8 "
            "D-3:4 F-3:2 A-3:2 G#3:4 E-3:4 "
            "B-2:2 D-3:2 E-3:2 G#3:2 A-3:8"),
}
CHORDS = {"a": [Am, F, C, G], "a2": [Am, F, Dm, E], "b": [Am, F, C, E], "b2": [Am, F, Dm, E]}
GLASS = m(".:6 E-3:2 .:6 A-3:2 .:6 C-3:2 .:6 G-3:2 .:6 E-3:2 .:6 C-3:2 .:6 B-2:2 .:6 E-3:2")
KIT = {"k": bd, "s": sd, "h": hh}


def bars(p, chords, groove):
    for bar, ch in enumerate(chords):
        root = ch[0]
        hi = root[:2] + "2"
        if groove:
            notes = "%s:3 %s:1 %s:2 %s:2 %s:2 %s:2 %s:2 %s:2" % (root, root, hi, root, hi, root, root, hi)
        else:
            notes = "%s:8 %s:8" % (root, hi)
        p.melody(1, bass, m(notes), start=bar * 16)
        p.melody(3, shim, [(ch[1], 16)], start=bar * 16, arp=ch[2])


def build(mel, groove=True, drums=True, sparkle=False):
    p = song.pattern()
    if mel:
        p.melody(0, bell, MEL[mel])
    elif sparkle:
        p.melody(0, glass, GLASS)
    bars(p, CHORDS[mel or "a"], groove)
    if drums:
        p.drums(2, "k.h.s.h.k.h.s.hh" * 3 + "k.h.s.h.k.k.s.ss", KIT)
    else:
        p.drums(2, "h...h...h...h.hh", KIT)
    return p


build(None, groove=False, drums=False, sparkle=True)   # 0 intro
build("a")                                             # 1
build("a2")                                            # 2
build("b")                                             # 3
build("b2")                                            # 4
build(None, groove=True, drums=True, sparkle=True)     # 5 break
song.order([0, 1, 2, 1, 2, 3, 4, 5, 3, 4])
song.save(OUT)
