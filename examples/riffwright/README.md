# Riffwright

A ProTracker music editor for AmigaOS 4.1, written in Boing BASIC. It loads, edits, plays
and saves `.mod` files: a keyboard-driven pattern editor drawn on a Canvas, a sample editor,
the order list and song settings, channel scopes and VU meters, 200 steps of undo.

![Riffwright on the AmigaOS 4 guest](docs/guest_pattern.png)

The editor is BASIC (about 3000 lines); the player is the runtime's `Boing.Audio` object (a
ProTracker player and mixer in C, playing through AHI in a task of its own). The
whole song model lives in BASIC and is mirrored into the player cell by cell, so every edit is
heard at once while the song plays.

## Running it

```
build/boing build examples/riffwright/Riffwright.bbp --target os4 -o Riffwright   # native, from the Mac
boing run Riffwright.bbp [song.mod]                                                # interpreted, on the Amiga
Riffwright [song.mod] [--play]
```

Copy `icons/Riffwright.info` next to the program and `icons/def_mod.info` as `song.mod.info`
for a project icon that opens the song in Riffwright. Two demo songs are in `demos/`.

The full manual is the AmigaGuide [Riffwright.guide](Riffwright.guide) (Help key). In short:

| | |
|---|---|
| piano keys | `Z S X D C V G B H N J M , L . ; /` and `Q 2 W 3 E R 5 T 6 Y 7 U I 9 O 0 P [ = ]` |
| Space | edit mode on/off (off: the keys only play) |
| F1/F2, F3/F4 | octave, sample |
| F5 / F6 / F7, Esc | play song / pattern / from the cursor row, stop |
| F9 | follow mode |
| F10, Amiga+1/2/3 | pattern editor, sample editor, song settings |
| Shift+cursor | select a block; Amiga+C/X/V/B copy, cut, paste, mix-paste |
| Amiga+T (Shift, Alt) | transpose the block up (down, by an octave) |
| Amiga+Z / Amiga+Y | undo / redo |
| Ctrl+Left/Right, Ctrl+Up/Down | order list position, pattern at the position |
| Ctrl+1..8 (Shift) | mute (solo) a channel |
| Amiga+O / S / N / Q | open, save, new, quit |

## What it does

- **Pattern editor**: note, sample and effect columns, hex entry left to right, edit step,
  insert/delete rows (one channel or all), block copy/cut/paste/mix-paste, transpose
  (semitone or octave, kept in ProTracker's C-1..B-3), interpolate effect parameters, set a
  block's sample, follow mode with smooth scrolling, mute/solo.
- **Song**: order list (grid editor in the song view, quick keys in the pattern view), title,
  start speed and tempo, length, restart position.
- **Samples**: waveform view with zoom, loop and play position; name, volume, finetune, loop
  start/length; load IFF 8SVX (plain and Fibonacci-delta), WAV (8/16 bit, mono/stereo;
  resampled to C-3's rate when faster than 22 kHz) and raw; save as 8SVX, WAV or raw;
  reverse, normalise, cut to the loop.
- **Files**: 31-sample ProTracker modules with 4 channels (M.K., M!K!, FLT4, 4CHN), 6 and 8
  channels (6CHN, 8CHN, FLT8, OCTA). A loaded file saves back byte for byte, including data
  after the last sample. Patterns not in the order list are kept when saving.
- **Playing**: song, pattern loop, from the cursor row; edits are heard at once; jam notes on
  the piano keys (also while the song plays), Return steps through rows; mute/solo; scopes
  and VU meters for every channel; a play cursor in the waveform.
- **Application**: undo/redo for every edit (200 steps), menus with shortcuts, asl requesters,
  Save/Discard/Cancel on unsaved changes, an ARexx port, drag and drop (a module opens, a sample
  file goes into the current sample), preferences in `ENV:Riffwright.prefs` (octave, follow
  mode, edit step, last drawer), AmigaGuide help (Help key), icons, and a project icon on
  newly saved songs that opens them in Riffwright.

ARexx (port `RIFFWRIGHT`): `PLAY [position]`, `STOP`, `LOAD file`, `SAVE [file]`,
`POSITION [n]` (returns the position playing), `TITLE`, `VERSION`.

```rexx
/* play a module from position 2 */
options results
address RIFFWRIGHT
'LOAD Work:music/song.mod'
'PLAY 2'
```

## How it is built

| File | |
|---|---|
| `Song.bas` | the song model and the .mod reader/writer |
| `Edit.bas` | every edit, with undo/redo (swap-based steps for cells, samples, song settings) and the clipboard |
| `Samples.bas` | 8SVX/WAV/raw load and save, sample operations, synthesised starter samples |
| `Player.bas` | the link to `Boing.Audio`: the song mirrored after a load (a temporary .mod through `LoadMusic`), each edit sent as it happens (`SetCell`, `CellPeriod` for odd periods, `SetSampleBytes`), transport, jam notes, scopes, VU |
| `View.bas` | all drawing |
| `Tracker.bas` | the editor: cursor, keys, views, what a frame shows |
| `Prefs.bas` | preferences |
| `main.afg`, `main.bas` | the window: keys and timer to the editor, requesters |

**Speed.** The pattern's text is drawn once into an image (64 rows) and a frame shows it with
one `DrawImagePart` at any pixel offset, so the pattern scrolls smoothly with a dozen Canvas
calls per frame whatever is in it. An edit redraws only its rows. While a song plays, the
next pattern in the order list is drawn into a second image, 8 rows per frame, so following
the song into it costs nothing. The order and sample lists are cached the same way.

### Measured on m1's guest

`Riffwright demos/harbour_lights.mod --bench 300`: the song plays in follow mode and 300
frames are drawn back to back with the pattern scrolling (a new pixel offset every frame), on
the 640 x 480 Canvas in its window (QEMU sam460ex on m1.local, unloaded):

| | fps | ms per frame (draw + blit) | worst frame, ms |
|---|---:|---:|---:|
| native (`boing build`) | 178 | 3.70 + 1.69 | 12.7 |
| VM (`boing run`) | 128 | 5.93 + 1.62 | 15.6 |
| VM `--jit` | 124 | 6.12 + 1.69 | 25.4 |

The window's timer asks for a frame every 20 ms (50 fps), so the interpreter uses about 40%
of the CPU time for a smoothly scrolling pattern, and the native build about 27%. The JIT
doesn't help here: a frame is a few dozen late-bound Canvas calls, not loops. Before the
frame drew only the regions that changed, the numbers were 136 / 95 / 94 fps.

## Tests

`make test` runs `tests/run.sh` (15 runs): each test through the VM, the VM with the JIT, and a native
build, compared with its `.out` file.

| Test | |
|---|---|
| `test_io` | .mod round trips byte-exact against reference files (`tests/ref`, written by an independent Python writer, `tools/mkref.py`: odd periods, sample numbers > 15, raw finetune bytes, data after the samples, 6 and 8 channels), the demo songs, bad files |
| `test_edit` | every editing operation, undo/redo, clipboard, the order list, song settings, samples, saving patterns not in the order list, the undo limit |
| `test_samples` | WAV (16-bit stereo 44.1 kHz, 8-bit mono), 8SVX (plain, Fibonacci-delta), raw: load, save, load back; reverse, normalise, crop |
| `test_player` | the song mirrored into `Boing.Audio` (every cell compared), edits while it plays (cells, odd periods, new patterns, undo, samples, order list), the pattern loop, jam notes, the sample play cursor, start speed/tempo, a PCM hash of a second of music (the "manual" device: the same on every platform) |
| `test_ui` | the editor driven by keys on an off-screen Canvas: jam and edit mode, hex entry, octave/sample keys, undo/redo, select/copy/paste/transpose, mute, the three views, frame drawing |

On the guest: `BB_GUEST=m1 tools/guest.py smoke` plays a demo, switches views and enters notes
by key (only while Riffwright's window is the active one), takes screenshots and checks that
it quits and leaves no process; `tools/guest.py bench N` times N frames native, in the VM and
with the JIT.

## Demo songs

`demos/harbour_lights.mod` (A minor, 125 BPM) and `demos/boing_shuffle.mod` (D, swung, 140
BPM) were composed for Riffwright (`tools/compose.py`, every note written there, every sample
synthesised) and are free to use for anything (CC0).
