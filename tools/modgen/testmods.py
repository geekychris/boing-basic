#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The test modules of tests/audio, made from synthesised samples (no recorded sound).

fx.mod: two patterns that use every ProTracker effect the player supports, so the PCM hash
in tests/audio/modplay.out covers them all. modlib.py is from amiga_mcp's
examples/tools/modgen (MIT, Copyright (c) 2026 Chris Collins).
"""
import os
from modlib import Song, m, cycle, pluck, kick, snare, hat

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, "..", "..", "tests", "audio")

song = Song("bb fx test", speed=6, bpm=125)
lead = song.instrument("lead", cycle("square", 32, duty=0.25), 40)
bass = song.instrument("bass", pluck("triangle", 64, cycles=20, sustain=0.5, amp=120), 60)
bd = song.instrument("kick", kick(), 64)
sd = song.instrument("snare", snare(), 48)
hh = song.instrument("hat", hat(), 34)
pad = song.instrument("pad", cycle("saw", 32), 30, finetune=3)

p0 = song.pattern()
# ch0: arpeggio, slides, tone portamento, vibrato
p0.put(0, 0, lead, "C-2", 0x0, 0x47)
p0.put(1, 0, None, None, 0x0, 0x47)
p0.put(4, 0, lead, "E-2", 0x1, 0x04)
p0.put(6, 0, None, None, 0x2, 0x06)
p0.put(8, 0, lead, "G-1", 0, 0)
p0.put(9, 0, lead, "G-2", 0x3, 0x10)
p0.put(10, 0, None, None, 0x3, 0x00)
p0.put(12, 0, lead, "A-2", 0x4, 0x46)
p0.put(13, 0, None, None, 0x4, 0x00)
p0.put(14, 0, None, None, 0x6, 0x02)
p0.put(16, 0, lead, "C-3", 0xE, 0x41)    # vibrato waveform ramp
p0.put(17, 0, None, None, 0x4, 0x38)
p0.put(20, 0, lead, "D-2", 0x5, 0x20)
p0.put(19, 0, lead, "B-1", 0, 0)
p0.put(22, 0, None, None, 0xE, 0x13)     # fine slide up
p0.put(23, 0, None, None, 0xE, 0x23)     # fine slide down
p0.put(24, 0, lead, "E-2", 0xE, 0x5D)    # finetune -3 on the note
p0.put(28, 0, lead, "F-2", 0xE, 0x32)    # glissando (ignored)
# ch1: tremolo, volume slides, sample offset
p0.put(0, 1, bass, "C-1", 0x7, 0x48)
p0.put(2, 1, None, None, 0x7, 0x00)
p0.put(4, 1, bass, "G-1", 0xA, 0x02)
p0.put(6, 1, None, None, 0xA, 0x30)
p0.put(8, 1, bass, "A-1", 0x9, 0x02)
p0.put(12, 1, bass, "A-1", 0x9, 0x00)    # offset memory
p0.put(14, 1, None, None, 0xE, 0xA4)
p0.put(15, 1, None, None, 0xE, 0xB8)
p0.put(16, 1, bass, "D-1", 0xE, 0x72)    # tremolo waveform square
p0.put(17, 1, None, None, 0x7, 0x66)
p0.put(24, 1, bass, "F-1", 0xC, 0x20)
# ch2: drums: retrigger, cut, delay
p0.drums(2, "k...s...", {"k": bd, "s": sd})
p0.put(10, 2, hh, "C-3", 0xE, 0x92)
p0.put(18, 2, hh, "C-3", 0xE, 0xC2)
p0.put(22, 2, sd, "C-3", 0xE, 0xD3)
# ch3: pan, volume, the pad
p0.put(2, 3, pad, "C-2", 0x8, 0x20)
p0.put(8, 3, pad, "E-2", 0x8, 0xE0)
p0.put(12, 3, pad, "G-2", 0xC, 0x10)
p0.put(16, 3, pad, "C-3", 0x8, 0x80)
p0.put(20, 3, None, None, 0xE, 0xC0)     # cut now
p0.put(32, 3, pad, "G-1", 0, 0)
p0.put(32, 0, None, None, 0xD, 0x00)     # break to the next position

p1 = song.pattern()
p1.melody(0, lead, m("C-2:2 E-2:2 G-2:2 C-3:2"))
p1.put(0, 1, bass, "C-1", 0xE, 0x60)     # loop start
p1.put(2, 1, bass, "G-1", 0xE, 0x62)     # loop twice back to row 0
p1.put(4, 2, bd, "C-3", 0xF, 0x03)       # speed 3
p1.put(6, 2, sd, "C-3", 0xE, 0xE2)       # pattern delay 2 rows
p1.put(8, 2, bd, "C-3", 0xF, 0xA0)       # bpm 160
p1.put(10, 3, pad, "E-2", 0xF, 0x06)     # speed 6
p1.put(16, 3, None, None, 0xB, 0x00)     # jump back to 0: the song's end
song.order([0, 1])
song.save(os.path.join(out, "fx.mod"))
