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

Status: **draft API (2026-11-08)**, implementation in progress on branch `sound`. Names
may still be added; the ones below will not change meaning without a note to the users
(bb-app-tracker, the game agents, bb-3d).

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
| `CpuLoad` | Long, R/O: the mixer's share of the CPU in 1/10 percent, measured over the last second (OS4) |

## Music

| Member | |
|---|---|
| `LoadMusic(path)` | load a module (ProTracker M.K./M!K!/4CHN/FLT4, 6CHN, 8CHN/OCTA/CD81, FLT8 is not supported); returns a song number |
| `NewSong([channels])` | an empty song (4 default, 6 or 8), one empty pattern, song length 1 |
| `SaveMusic song, path` | write the song as a ProTracker module (M.K. for 4 channels, 6CHN, 8CHN) |
| `FreeMusic song` | stops it first if it plays |
| `PlayMusic song [, position [, row]]` | start (restart) a song |
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
| `JumpTo position [, row]` | jump (takes effect at the next row) |
| `Speed` | Long: ticks per row (1..31, set by Fxx too) |
| `Tempo` | Long: BPM (32..255) |
| `Mute(channel)` | Boolean, read/write |
| `Solo channel` | only that channel sounds; `Solo -1` = all again (clears mutes) |
| `ChannelVolume(channel)` | Long 0..64, R/O: the channel's current volume (after effects) |
| `ChannelVU(channel)` | Long 0..64, R/O: the channel's peak level over the last chunk mixed (VU meter) |
| `ChannelNote(channel)` | Long, R/O: the last note triggered on the channel (1..36, 0 none) |
| `ChannelSample(channel)` | Long, R/O: its sample (1..31) |
| `Scope(channel, buf(), n)` | fill `buf(0..n-1)` (Long or Integer array) with the channel's last n output samples, -128..127, n up to 1024. Channel -1 = the mixed left+right output, -32768..32767 |

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
| `LoadSample song, s, path` | an 8SVX/WAV/raw file into sample s (converted to 8-bit mono, rate kept as is: set the note to taste) |
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

Glimmerfield (`examples/glimmerfield`) has music and effects, with M (music) and S (sound)
switches. `tests/audio/` renders test modules and compares PCM hashes.

## CPU cost

(to be measured on the m1 guest)
