# Sound: the Audio object

Music (ProTracker modules) and sound effects for games and the tracker. One object,
`Boing.Audio`, drives one software mixer:

```basic
Dim au As Object
Set au = CreateObject("Boing.Audio")     ' every Audio object is the same mixer
song = au.LoadMusic("PROGDIR:glimmer.mod")
au.PlayMusic song
boom = au.LoadSound("PROGDIR:boom.wav")  ' 8SVX, WAV, or raw
...
au.PlaySound boom, 48, -20               ' volume 0..64, pan -64 (left) .. 64 (right)
```

Status (2026-11-08): implemented as described here, on the Mac (null/wav/manual devices) and
AmigaOS 4 (AHI). Names may still be added; the ones below will not change meaning without a
note to their users (bb-app-tracker, the game agents, bb-3d).

## How it works

- The player and mixer are portable C (`src/runtime/audio/`): a ProTracker player derived
  from amiga3d's `modplay.c`, plus sound-effect voices, mixed in integer arithmetic to
  signed 16-bit stereo. The same song gives **the same samples on every platform** (the
  tests hash the PCM).
- Output on AmigaOS 4: `ahi.device`, fed by a **mixer task of its own** (two linked
  `CMD_WRITE` requests, the task sleeps in `Wait()` between chunks; no busy waiting, no
  per-frame call needed from the program). Calls from BASIC take a mutex, so a program
  edits songs and starts sounds while the music plays.
- Output on the Mac/Linux: a null device (time-driven: the music position advances with
  the clock, nothing is heard), a WAV file, or manual rendering (`Render`) for tests.
- No AHI (or no free unit) just means silence: every call still works and positions still
  advance.
- Rate: 22050 Hz by default (`Open`'s second argument). Mixing costs about the same per
  voice whatever the program does; see "CPU cost" below once measured.

## Units

| | |
|---|---|
| volume | 0..64 everywhere (as on Paula); master volumes too |
| pan | -64 = left, 0 = centre, 64 = right |
| rate | samples per second (Hz) |
| note | 1..36 = ProTracker's C-1 .. B-3 (periods 856 .. 113); 0 = no note. `NoteName(n)` gives "C-1", `NoteFromName("C#2")` the number |
| channel | music channels 0 .. Channels-1 (4, 6 or 8) |
| song, sound | numbers from 1 returned by `LoadMusic`/`NewSong` and `LoadSound`/`CreateSound`; 0 = none |
| voice | a playing sound effect, number returned by `PlaySound` |

Errors: 53 file not found, 380 "invalid property value" for a file that is not a
module or sound, 9 for a song/sound/pattern/channel number out of range, 5 for other bad
arguments.

## Device

| Member | |
|---|---|
| `Open [device [, rate]]` | `""` = the platform default (AHI on OS4, null elsewhere), `"null"`, `"wav:path"` (write everything mixed to a WAV file), `"manual"` (only `Render` mixes: tests). Opens automatically with the default on first use |
| `Close` | stop everything, close the device (and finish the WAV file) |
| `Device` | String, R/O: e.g. `ahi`, `null`, `wav`, `manual`, `none` (no AHI found) |
| `Rate` | Long, R/O |
| `Render frames` | mix `frames` stereo frames now (manual and wav devices); returns nothing |
| `PcmHash` | Long, R/O: a checksum of every frame mixed since `Open` (or `ResetHash`) |
| `ResetHash` | |
| `RenderToWav song, path [, maxSeconds]` | render a song from its start into a WAV file, without playing it, until it ends (or maxSeconds, default 600): the tracker's export |
| `Volume` | Long 0..64: master volume (default 64) |
| `CpuLoad` | Long, R/O: the time the mixer task spent mixing over the last second, in 1/10 percent (AHI on OS4; -1 elsewhere) |

## Music

| Member | |
|---|---|
| `LoadMusic(path)` | load a module (ProTracker M.K./M!K!/4CHN/FLT4, 6CHN, 8CHN/OCTA/CD81, FLT8 is not supported); returns a song number |
| `NewSong([channels])` | an empty song (4 default, 6 or 8), one empty pattern, song length 1 |
| `SaveMusic song, path` | write the song as a ProTracker module (M.K. for 4 channels, 6CHN, 8CHN) |
| `FreeMusic song` | stops it first if it plays |
| `PlayMusic song [, position [, row]]` | start (restart) a song, at its `SongSpeed`/`SongTempo` |
| `PlayPattern song, pattern [, row]` | loop one pattern (the tracker's play-pattern key); `Pattern` reports it, `Bxx`/`Dxx` stay in it, `SongEnded` doesn't count |
| `StopMusic` | stop; channels go quiet |
| `Pause` / `Resume` | hold the music (effects go on) |
| `Playing` | Boolean, R/O: a song is playing (paused counts as playing) |
| `Paused` | Boolean, R/O |
| `CurrentSong` | Long, R/O: the song playing, 0 = none |
| `MusicVolume` | Long 0..64 (default 48: a bit under the effects) |
| `MusicEnabled` | Boolean: False mutes the music but keeps it running (a game's music switch) |
| `Loop` | Boolean (default True): at the song's end start again (at the loop target of a backward `Bxx`); False = stop at the end |
| `SongEnded` | Long, R/O: how many times the song reached its end since `PlayMusic` (works with Loop on: a game changes tune on it) |
| `Position` | Long: the order-list position playing; setting it jumps there (row 0) |
| `Row` | Long: the row playing (0..63); setting it jumps to that row of the current position |
| `Pattern` | Long, R/O: the pattern number at the current position |
| `Tick` | Long, R/O: tick within the row |
| `JumpTo position [, row]` | jump there now (the row is played from its start); `Position = p` is `JumpTo p, 0`, `Row = r` jumps within the current position |
| `Speed` | Long: ticks per row (1..31, set by Fxx too) |
| `Tempo` | Long: BPM (32..255) |
| `Mute(channel)` | Boolean, read/write |
| `Solo channel` | only that channel sounds; `Solo -1` = all again (clears mutes) |
| `ChannelVolume(channel)` | Long 0..64, R/O: the channel's current volume (after effects) |
| `ChannelVU(channel)` | Long 0..64, R/O: the channel's peak level over the last chunk mixed (VU meter) |
| `ChannelNote(channel)` | Long, R/O: the last note triggered on the channel (1..36, 0 none) |
| `ChannelSample(channel)` | Long, R/O: its sample (1..31) |
| `ChannelPos(channel)` | Long, R/O: the play offset in the channel's sample in bytes, -1 when silent (a waveform view's cursor) |
| `Scope(channel, n)` | a Long array `(0 To n-1)` of the channel's last n output samples (oldest first), -128..127, n up to 1024: `Dim sc() As Long: sc = au.Scope(0, 256)`. Channel -1 = the mixed output ((left + right) / 2), -32768..32767. (A function, not a buffer to fill: arrays reach late-bound calls as copies) |

## Live playing (tracker keyboard, jingles)

| Member | |
|---|---|
| `PlayNote channel, note, sample [, volume [, effect, param]]` | trigger a note of the current (or last played) song's sample on a music channel now, through the channel's normal state, so effects work. Works while the music is stopped too; the song's own next note on that channel replaces it |
| `PlayRow song, pattern, row` | play one row (all channels) of a pattern now, without starting the song: the tracker's step-through |
| `NoteOff channel` | silence a music channel |
| `EditSong song` | which song `PlayNote` uses when no song plays (default: the last loaded or played) |

## Song data (editing works while the song plays)

All take the song number first. Patterns are numbered from 0, rows 0..63, channels from 0,
samples 1..31. Changes are heard at once (a playing note keeps its sample; a sample whose data
is replaced is cut on channels playing it).

| Member | |
|---|---|
| `SongName(song)` | String, read/write (20 chars) |
| `Channels(song)` | Long, R/O |
| `SongSpeed(song)`, `SongTempo(song)` | Long, read/write: what `PlayMusic` starts with before any `Fxx` (6 and 125) |
| `SongRestart(song)` | Long 0..127, read/write: the restart byte (951), kept as loaded and written on save (127 = none) |
| `SongLength(song)` | Long 1..128, read/write: the used part of the order list |
| `Order(song, position)` | Long, read/write: the pattern at that order-list position (0..127) |
| `PatternCount(song)` | Long, R/O: patterns stored (highest used + 1) |
| `AddPattern(song)` | a new empty pattern; returns its number (up to 100 for 4 ch) |
| `ClearPattern song, pattern` | |
| `CopyPattern song, from, to` | |
| `CellNote(song, pattern, row, ch)` | Long, read/write: 0 or 1..36 |
| `CellPeriod(song, pattern, row, ch)` | Long, read/write: the raw period (0 = none), for periods off the note table |
| `CellSample(song, pattern, row, ch)` | Long, read/write: 0..31 |
| `CellEffect(song, pattern, row, ch)` | Long, read/write: 0..15 |
| `CellParam(song, pattern, row, ch)` | Long, read/write: 0..255 |
| `Cell(song, pattern, row, ch)` | Long, read/write: the four packed: note * 2^24 + sample * 2^16 + effect * 2^8 + param (copy/paste in one call) |
| `SetCell song, pattern, row, ch, note, sample, effect, param` | all four at once |
| `SampleName(song, s)` | String, read/write (22 chars) |
| `SampleLength(song, s)` | Long, read/write: bytes (even, up to 131070); growing pads with silence |
| `SampleVolume(song, s)` | Long 0..64, read/write |
| `SampleFinetune(song, s)` | Long -8..7, read/write |
| `SampleLoopStart(song, s)`, `SampleLoopLength(song, s)` | Long, read/write: bytes (loop length 0 or 2 = no loop) |
| `SampleData(song, s, index)` | Long -128..127, read/write: one byte of the sample |
| `SetSampleBytes song, s, bytes() [, n]` | the sample's data from an array in one call: Byte (signed 8-bit as stored, 128..255 = -128..-1), or Integer/Long (-128..127); the length becomes n (default: the whole array) |
| `GetSampleBytes(song, s)` | the sample's data as a Byte array `(0 To len-1)` (Empty for an empty sample) |
| `LoadSample song, s, path` | an 8SVX or WAV file (raw isn't accepted here: load it with `LoadSound(path, rate, format)` and use `SetSampleFromSound`) into sample s (converted to 8-bit mono, rate kept as is: set the note to taste) |
| `SetSampleFromSound song, s, sound` | a sound (below) as sample s |
| `NoteName(note)`, `NoteFromName(name)`, `NotePeriod(note [, finetune])` | helpers |

The mixer reads song data with the mutex held, so editing from BASIC between frames is safe.
Big edits (a whole pattern) are cheapest with `Cell`/`SetCell`.

## Sound effects

| Member | |
|---|---|
| `LoadSound(path [, rate [, format]])` | IFF 8SVX, RIFF WAV (8/16-bit, mono/stereo, PCM; stereo is mixed down), or raw. Raw needs `format`: `"s8"` (signed 8-bit, Amiga), `"u8"`, `"s16le"`, `"s16be"`, and `rate` (default 8363). Returns a sound number |
| `CreateSound(length [, rate [, bits]])` | an empty sound: length in samples, rate default 22050, bits 8 or 16 (default 16) |
| `SoundData(sound, index)` | Long, read/write: one sample (-128..127 or -32768..32767) |
| `SoundLength(sound)`, `SoundRate(sound)`, `SoundBits(sound)` | R/O (`SoundRate` writable) |
| `SoundLoop(sound)` | Boolean, read/write: loop the whole sound (or the loop below) when played |
| `SoundLoopStart(sound)`, `SoundLoopLength(sound)` | Long, read/write, in samples |
| `SynthTone(ms, f0, f1 [, volume [, wave]])` | a new 16-bit sound: a tone sweeping f0 -> f1 Hz with a short fade; wave 0 triangle (default), 1 square, 2 sine, 3 saw. Returns a sound number (games' laser/pickup sounds without files) |
| `SynthNoise(ms [, volume [, smooth [, attack_ms]]])` | a new sound: decaying noise (explosions); smooth 0..15 low-passes it |
| `FreeSound sound` | stops its voices |
| `PlaySound(sound [, volume [, pan [, rate [, loop]]]])` | play on a free effect voice; returns the voice number (0 if all 8 voices are busy with equal or higher priority). rate overrides the sound's rate (pitch), loop overrides SoundLoop |
| `PlaySoundPri(sound, priority [, volume [, pan [, rate [, loop]]]])` | the same with a priority (default 0): a voice is stolen only from a lower or equal priority |
| `StopVoice voice` | |
| `StopSounds` | all effect voices |
| `VoicePlaying(voice)` | Boolean, R/O |
| `VoiceVolume(voice)`, `VoicePan(voice)`, `VoiceRate(voice)` | Long, read/write: change a playing sound (engine pitch, fades) |
| `SoundVolume` | Long 0..64: master for the effects (default 64) |
| `SoundEnabled` | Boolean: False = `PlaySound` does nothing (a game's effects switch) |
| `Voices` | Long, R/O: the number of effect voices (8) |

Voice numbers are unique while the program runs (a voice that ended is not reused under the
same number), so `StopVoice` on an old voice is harmless.

## amiga3d-style effects

For ports of the amiga3d C games: the same calls and arithmetic as `a3d_sound.c`
(`a3_sfx_define`, `a3_tone`, `a3_noise`, `a3_sfx`), so the effects are byte for byte the
originals'. The buffers are 8-bit, played at 11 822 Hz (Paula period 300).

| Member | |
|---|---|
| `SfxDefine id, length [, volume [, priority]]` | id 0..63: a silent buffer of length samples (even); redefining replaces it |
| `SfxTone id, offset, n, f0, f1, amp [, fade]` | `a3_tone` into samples offset..offset+n-1: a triangle sweeping f0 -> f1 Hz, fading over the last `fade` samples |
| `SfxNoise id, offset, n, amp [, lowpass [, attack]]` | `a3_noise`: noise (one generator for the program, seeded as in a3d) low-passed, rising over `attack` samples, then dying away |
| `Sfx(id [, volume])` | play it on a free voice with its priority; returns the voice (0: none, or effects off). Cheap: call it as often as you like |
| `SfxSound(id)` | the sound number behind it (for `PlaySound` with pan or rate, `SoundData`...) |

```basic
au.SfxDefine 2, 2400, 48, 20                    ' LAND: three tones
au.SfxTone 2, 0, 800, 523, 523, 90, 100
au.SfxTone 2, 800, 800, 659, 659, 90, 100
au.SfxTone 2, 1600, 800, 784, 784, 90, 200
...
v = au.Sfx(2)
```

A precomputed sample at a Paula period: `au.PlaySound snd, vol, 0, 3546895 \ period`.

On the Mac every call works the same with no sound device (the "null" device mixes silently
by the clock, so positions advance); `Open "manual"` makes it deterministic for tests.

## Cost of calls

Under QEMU a late-bound call costs 20-50 us (docs/performance.md), so read the play state once
per frame with the batched calls, and keep the Audio object in a module-level variable:

| Member | |
|---|---|
| `State()` | a Long array (0 To 55): 0 Playing, 1 Paused (True = -1), 2 Position, 3 Row, 4 Pattern, 5 Tick, 6 Speed, 7 Tempo, 8 SongEnded, 9 CurrentSong, 10 Channels, 11 CpuLoad, 12-15 reserved; channel c at 16 + c * 5: VU, note, sample, volume, ChannelPos |
| `Scopes(n [, channels])` | one Long array with every channel's `Scope(c, n)`: channel c at c * n (channels = the song's, default) |

Measured on the m1b guest (2026-11-09): a scalar read 0.9 us; `State()`, `Scope()` and
`Scopes()` about 40 us each in the VM but about 1 us in a native build. bb-core traced the VM
figure to the QEMU guest's small software-refilled TLB (the array code's extra pages), not to
copying; real X5000/A1222 hardware shouldn't see it. So in the VM call them once a frame.


Reading the play state (`Position`, `Row`, `Pattern`, `Tick`, `Speed`, `Tempo`, `Playing`,
`Paused`, `SongEnded`, `Mute`, `Channel*`, `Scope`, `VoicePlaying`, `CpuLoad`) takes no lock:
the values are words the mixer task writes, at most one chunk (40 ms) old. Every other call
takes the mixer's mutex for its duration; the mixer holds it while it mixes a chunk (about
0.4 ms on the m1 guest for 4 channels), so a call waits at most that long.

## Mixing

Music channels: Amiga panning (channels 0 and 3 left, 1 and 2 right; for 6/8 channels the
pattern repeats), each side with a quarter of the other side mixed in (headphones). `8xx`
(non-ProTracker pan, 00 = left, 80 = centre, FF = right) sets a channel's pan explicitly.
Effects: their pan. Then master volume and clipping to 16 bits.

## ProTracker support

Effects 0 arpeggio, 1/2 slides, 3 tone portamento, 4 vibrato, 5, 6, 7 tremolo, 8 pan,
9 sample offset, A volume slide, B position jump, C volume, D pattern break, F speed/tempo,
E1/E2 fine slides, E3 glissando (ignored), E4/E7 vibrato/tremolo waveform, E5 finetune,
E6 pattern loop, E9 retrigger, EA/EB fine volume slides, EC note cut, ED note delay,
EE pattern delay. E0 (filter) and EF are ignored. Timing is CIA (BPM) timing. Samples aren't
interpolated, as on Paula.

## Examples

Glimmerfield (`examples/glimmerfield`, `Sound.bas`) has music and effects, with M (music)
and S (sound) switches: the music is `glimmer.mod`, made for the game by
`tools/modgen/glimmerfield.py`; the effects are made at start-up with `SynthTone` and
`SynthNoise`.

```basic
' a jingle without a file: play row 0 of pattern 3 of a song
au.PlayRow song, 3, 0
' an engine: a looped noise whose pitch follows the speed
eng = au.PlaySound(hiss, 20, 0, 8000, True)
au.VoiceRate(eng) = 8000 + speed * 40
```

## Files and tests

| | |
|---|---|
| `src/runtime/audio/bbmod.c` | the ProTracker player and song data (from amiga3d's `modplay.c`) |
| `src/runtime/audio/bbmix.c` | the mixer: music + 8 effect voices, master volume, PCM hash, WAV header |
| `src/runtime/audio/bbsound.c` | 8SVX / WAV / raw loaders, `SynthTone` / `SynthNoise` |
| `src/runtime/audio.c` | the `Audio` object, the null / wav / manual devices |
| `src/runtime/os4/audio_os4.c` | AHI output from a mixer process |
| `tools/modgen/` | `modlib.py` (from amiga_mcp's `examples/tools/modgen`), the test module and Glimmerfield's tune |

`make test` runs `tests/audio/*.bas` (VM, JIT and native): `modplay` renders `fx.mod`, which
uses every supported effect, and hashes the PCM; `sfx` covers the loaders, synthesis, voices,
priorities and switches; `edit` builds an 8-channel song from BASIC, saves, reloads and plays
it, edits it while it plays, and plays live notes and rows. `tests-os4/audio/audio.bas`
(`tools/os4guest.py bas`) renders the same PCM on AmigaOS 4 (the hashes must match the Mac's)
and plays through AHI.

The player was checked against the original `modplay.c` on the amiga3d games' modules: the
same samples within 1 LSB (rounding).

## CPU cost

Measured on the m1 guest (QEMU sam460ex on a Mac mini M1, AHI on the emulated ES1370,
2026-11-08) with `examples/glimmerfield/tools/guest_sound.py`: Glimmerfield `--bench 1500`
(native build), once silent and once with the music playing (4 channels, 22050 Hz):

| | ms/frame | mixer task |
|---|---|---|
| no sound | 2.023 | |
| music on | 2.035 (+0.012 ms, +0.6 %) | `CpuLoad` 0.9 % |

The guest's audio output was recorded during the run with QEMU's HMP `wavcapture` on the
`snd0` audiodev: 3.1 s, RMS 583, peak 2621 (MusicVolume 40, master 64), so sound is produced.
Each extra effect voice costs about as much as a music channel.
