# Sound and music: Audio

This chapter is about the Audio object, which plays music and sound effects. It plays
ProTracker modules (MOD files), plays sound effects loaded from files or made by the program,
and lets a program build and change songs note by note, as a tracker does. It also renders
sound to WAV files, and can mix without any sound hardware, which makes sound code testable.

## The Audio object

`CreateObject("Boing.Audio")` gives you the Audio object. There is only one sound mixer: every
Audio object you create drives the same one, so it does not matter which module creates it.
Declare the variable `As Audio` (then `boing check` reports misspelt member names), or `As
Object`.

*Listing 16.1* (`examples/book/ch16-audio/listing-16-01.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim au As Audio, laser As Long, boom As Long, v1 As Long, v2 As Long
    Set au = CreateObject("Boing.Audio")
    au.Open "manual"                         ' only Render mixes: the same result every run
    Print "device "; au.Device; ", rate"; au.Rate; ", voices"; au.Voices

    laser = au.SynthTone(150, 1800, 300, 60, 1)      ' 150 ms, 1800 Hz falling to 300, square
    boom = au.SynthNoise(600, 64, 6)                 ' 600 ms of noise, smoothed
    Print "laser:"; au.SoundLength(laser); "samples at"; au.SoundRate(laser); "Hz,"; au.SoundBits(laser); "bits"
    Print "boom: "; au.SoundLength(boom); "samples"

    v1 = au.PlaySound(laser, 48, -32)                ' volume 48, a little to the left
    v2 = au.PlaySound(boom, 64, 40)                  ' full volume, to the right
    Print "voices"; v1; v2; " playing:"; au.VoicePlaying(v1); au.VoicePlaying(v2)
    au.Render 22050 \ 5                              ' mix 0.2 seconds
    Print "after 0.2 s:"; au.VoicePlaying(v1); au.VoicePlaying(v2)
    au.Render 22050
    Print "after 1.2 s:"; au.VoicePlaying(v2)
    Print "PCM hash"; au.PcmHash
    au.Close
End Sub
```

```output
device manual, rate 22050 , voices 8 
laser: 3307 samples at 22050 Hz, 16 bits
boom:  13230 samples
voices 1  2  playing:TrueTrue
after 0.2 s:FalseTrue
after 1.2 s:False
PCM hash 1631454528 
```

In a real program you leave out `au.Open "manual"` (or call `au.Open` with no arguments): the
sound then goes to the speakers, and you never call `Render`.

## How it works

The music player and the mixer are written in portable C. They mix the music channels and up
to 8 sound-effect voices into 16-bit stereo, using integer arithmetic only, so the same song
gives exactly the same samples on every machine.

On AmigaOS 4 the sound goes out through `ahi.device`. The mixing is done by a task of its
own that sleeps between chunks of sound, so the music keeps playing smoothly while your
program does other things, and you never need to call anything each frame to keep it going.
You can start sounds and edit songs while the music plays: every call waits for the mixer to
finish its current chunk (well under a millisecond) and then takes effect.

If AHI is not set up, or has no free unit, the program still runs: `Device` is `"none"`,
nothing is heard, and every call works as usual. Check `Device` if you want to tell the user.

On other systems (the host you cross-develop on) there is no sound output: the default device
is `"null"`, which plays silently by the clock, so song positions move on as they would on the
Amiga.

## Units

| | |
|---|---|
| volume | 0 to 64 everywhere, as on the Amiga's Paula chip |
| pan | -64 = left, 0 = centre, 64 = right |
| rate | samples per second (Hz) |
| note | 1 to 36: ProTracker's C-1 to B-3; 0 = no note. `NoteName(13)` is `"C-2"`, `NoteFromName("C#2")` gives 14 |
| channel | a music channel, 0 to `Channels` - 1 (4, 6 or 8 channels) |
| song, sound | numbers from 1, returned by `LoadMusic`/`NewSong` and `LoadSound`/`CreateSound`/`SynthTone`... |
| voice | a sound effect that is playing, the number `PlaySound` returned |
| pattern | numbered from 0; 64 rows (0 to 63) |
| sample | a song's instruments, 1 to 31 |

**Errors**: 53 file not found; 380 a file that is not a module or a sound; 9 a song, sound,
pattern, channel or sample number out of range; 5 other bad arguments.

## The device

| Member | What it does |
|---|---|
| `Open [device [, rate]]` | open the sound output. `""` (or nothing) = the normal output (AHI on AmigaOS 4, `"null"` elsewhere); `"null"` = silent, by the clock; `"wav:path"` = write everything that is mixed to a WAV file; `"manual"` = mix only when `Render` is called (tests). `rate` defaults to 22050. The first call that needs the mixer opens the normal output by itself |
| `Close` | stop everything and close the device (and finish the WAV file) |
| `Device` | String, read-only: `"ahi"`, `"none"` (no AHI), `"null"`, `"wav"` or `"manual"` |
| `Rate` | Long, read-only: the mixing rate |
| `Volume` | Long 0..64: the master volume (64) |
| `Render frames` | mix this many stereo samples now (`"manual"` and `"wav:"` devices) |
| `RenderToWav song, path [, maxSeconds]` | render a song from its start into a WAV file, without playing it, until it ends (or `maxSeconds`, default 600) |
| `PcmHash` | Long, read-only: a checksum of everything mixed since `Open` or `ResetHash` |
| `ResetHash` | start the checksum again |
| `CpuLoad` | Long, read-only: the processor time the mixer used over the last second, in tenths of a percent (AmigaOS 4 with AHI; -1 elsewhere) |

The `"manual"` device and `PcmHash` are for testing sound code: render a known number of
samples and compare the checksum with the value from a run you have listened to.

## Sound effects

### Getting sounds

| Member | What it does |
|---|---|
| `LoadSound(path [, rate [, format]])` | load an IFF 8SVX or WAV file (8 or 16-bit, mono or stereo; stereo is mixed to mono), or raw sample data. For raw data give `format`: `"s8"` (signed 8-bit, the Amiga's usual), `"u8"`, `"s16le"` or `"s16be"`, and `rate` (default 8363). Returns a sound number |
| `CreateSound(length [, rate [, bits]])` | a silent sound of `length` samples (rate default 22050, bits 8 or 16, default 16) to fill with `SoundData` |
| `SynthTone(ms, f0, f1 [, volume [, wave]])` | a new sound: a tone lasting `ms` milliseconds that sweeps from f0 to f1 Hz, with a short fade. `wave`: 0 triangle (default), 1 square, 2 sine, 3 sawtooth |
| `SynthNoise(ms [, volume [, smooth [, attack]]])` | a new sound: noise that dies away (explosions, crashes). `smooth` 0..15 makes it duller; `attack` = milliseconds to fade in |
| `FreeSound sound` | free a sound (any voices playing it stop) |

`SynthTone` and `SynthNoise` give a game its laser, pick-up and explosion sounds without any
sample files: make them once at start-up.

### A sound's data

| Member | What it does |
|---|---|
| `SoundData(sound, index)` | one sample, read/write: -128..127 for 8-bit, -32768..32767 for 16-bit |
| `SoundLength(sound)`, `SoundBits(sound)` | read-only |
| `SoundRate(sound)` | read/write: the rate it plays at normally |
| `SoundLoop(sound)` | Boolean, read/write: loop when played |
| `SoundLoopStart(sound)`, `SoundLoopLength(sound)` | read/write, in samples: the part that loops (the whole sound when the length is 0) |

This program makes a sound sample by sample, records it through the `"wav:"` device, and
loads the file back:

*Listing 16.2* (`examples/book/ch16-audio/listing-16-02.bas`)

<!-- run -->
```basic
' Make a sound sample by sample, record it to a WAV file, and load the file back
Option Explicit

Const PI As Double = 3.14159265358979

Sub Main()
    Dim au As Audio, snd As Long, i As Long, back As Long, n As Long
    Set au = CreateObject("Boing.Audio")
    snd = au.CreateSound(2205, 22050, 16)            ' 0.1 s, 16-bit
    For i = 0 To 2204                                ' a 440 Hz sine, fading out
        au.SoundData(snd, i) = CLng(Sin(2 * PI * 440 * i / 22050) * 20000 * (2205 - i) / 2205)
    Next i
    Print "sample 50 ="; au.SoundData(snd, 50)

    au.Open "wav:beep.wav"                           ' everything mixed goes to this file
    au.PlaySound snd, 64
    au.Render 4410                                   ' 0.2 s
    au.Close                                         ' finishes the file
    Print "beep.wav is"; FileLen("beep.wav"); "bytes"

    au.Open "manual"
    back = au.LoadSound("beep.wav")
    Print "loaded:"; au.SoundLength(back); "samples,"; au.SoundBits(back); "bits,"; au.SoundRate(back); "Hz"
    For i = 0 To au.SoundLength(back) - 1
        If Abs(au.SoundData(back, i)) > 1000 Then n = n + 1
    Next i
    Print n; "loud samples"
    Kill "beep.wav"
End Sub
```

```output
sample 50 =-278 
beep.wav is 17684 bytes
loaded: 4410 samples, 16 bits, 22050 Hz
 1880 loud samples
```

### Playing sounds

| Member | What it does |
|---|---|
| `PlaySound(sound [, volume [, pan [, rate [, loop]]]])` | play a sound on a free voice; returns the voice number, or 0 if none could be had. `rate` changes the pitch (twice the rate = an octave higher); `loop` overrides `SoundLoop` |
| `PlaySoundPri(sound, priority [, volume [, pan [, rate [, loop]]]])` | the same with a priority (`PlaySound` uses 0) |
| `StopVoice voice` | stop one voice |
| `StopSounds` | stop all sound effects |
| `VoicePlaying(voice)` | Boolean, read-only |
| `VoiceVolume(voice)`, `VoicePan(voice)`, `VoiceRate(voice)` | read/write: change a sound while it plays (an engine's pitch, a fade) |
| `SoundVolume` | Long 0..64: the volume of all effects (64) |
| `SoundEnabled` | Boolean: False makes `PlaySound` do nothing (a game's "effects off" switch) |
| `Voices` | Long, read-only: the number of effect voices, 8 |

**Priorities.** There are 8 effect voices. When all are busy, a new sound takes the voice of
a sound with the same or a lower priority; if every voice has a higher priority, the new
sound is not played and the call returns 0. Give important sounds (the player's death) a
higher priority than frequent ones (shots).

Voice numbers are never reused while the program runs, so calling `StopVoice` or
`VoicePlaying` with the number of a voice that has already finished is harmless.

*Listing 16.3* (`examples/book/ch16-audio/listing-16-03.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim au As Audio, hum As Long, ping As Long, i As Long, v As Long, eng As Long
    Set au = CreateObject("Boing.Audio")
    au.Open "manual"
    hum = au.SynthTone(200, 110, 110, 40, 2)
    au.SoundLoop(hum) = True                       ' loops until stopped
    ping = au.SynthTone(80, 2000, 2000)
    For i = 1 To 8                                 ' fill all 8 voices at priority 5
        v = au.PlaySoundPri(hum, 5, 20)
    Next i
    Print "all busy: low priority gets voice"; au.PlaySoundPri(ping, 1)
    Print "high priority gets voice"; au.PlaySoundPri(ping, 9)
    au.StopSounds

    eng = au.PlaySound(hum, 30, 0, 11025, True)    ' half speed: an octave lower
    au.VoiceRate(eng) = 16000                      ' change the pitch while it plays
    au.VoiceVolume(eng) = 50
    Print "engine voice"; eng; " rate"; au.VoiceRate(eng); " volume"; au.VoiceVolume(eng)
    au.StopVoice eng
    Print "stopped:"; Not au.VoicePlaying(eng)

    au.SoundEnabled = False                        ' the game's "effects off" switch
    Print "with effects off PlaySound gives"; au.PlaySound(ping)
    au.SoundEnabled = True
End Sub
```

```output
all busy: low priority gets voice 0 
high priority gets voice 9 
engine voice 10  rate 16000  volume 50 
stopped:True
with effects off PlaySound gives 0 
```

To play a sample at a given Amiga Paula period, use the rate 3546895 / period:
`au.PlaySound snd, 64, 0, 3546895 \ period`.

### Effects in the amiga3d style

These members make and play effects exactly as the amiga3d C games do, for programs ported
from them. Each effect is an 8-bit buffer with an id from 0 to 63, played at 11822 Hz.

| Member | What it does |
|---|---|
| `SfxDefine id, length [, volume [, priority]]` | a silent buffer of `length` samples (even); defining an id again replaces it |
| `SfxTone id, offset, n, f0, f1, amp [, fade]` | write a triangle tone sweeping from f0 to f1 Hz into samples offset to offset + n - 1, fading over the last `fade` samples |
| `SfxNoise id, offset, n, amp [, lowpass [, attack]]` | write noise, smoothed by `lowpass`, rising over `attack` samples and then dying away |
| `Sfx(id [, volume])` | play it with its priority; returns the voice (0 if none, or effects are off). Cheap enough to call as often as you like |
| `SfxSound(id)` | read-only: the sound number behind an effect, to use with `PlaySound` or `SoundData` |

## Music

### Playing a module

*Listing 16.4* (`examples/book/ch16-audio/listing-16-04.bas`)

```basic
Option Explicit

Dim au As Audio
Dim song As Long, answer As String

Sub Main()
    Set au = CreateObject("Boing.Audio")
    au.Open
    If au.Device = "none" Then Print "No AHI device: set one up in Prefs/AHI"
    On Error Resume Next
    song = au.LoadMusic("PROGDIR:tune.mod")
    If Err.Number <> 0 Then
        Print "Can't load the music: error"; Err.Number
        Exit Sub
    End If
    On Error GoTo 0
    au.MusicVolume = 40
    au.PlayMusic song
    Print "Playing "; au.SongName(song); ". Press Return to stop."
    Line Input answer
    au.StopMusic
End Sub
```

| Member | What it does |
|---|---|
| `LoadMusic(path)` | load a module: ProTracker 4-channel (M.K., M!K!, 4CHN, FLT4), 6CHN, and 8-channel (8CHN, OCTA, CD81). FLT8 is not supported. Returns a song number |
| `NewSong([channels])` | a new empty song of 4 (default), 6 or 8 channels, with one empty pattern and a song length of 1 |
| `SaveMusic song, path` | save a song as a ProTracker module (M.K. for 4 channels, 6CHN, 8CHN) |
| `FreeMusic song` | free a song (stopping it first if it plays) |
| `PlayMusic song [, position [, row]]` | start a song from the beginning (or from a position and row), at its own speed and tempo |
| `PlayPattern song, pattern [, row]` | play one pattern over and over (a tracker's "play pattern") |
| `StopMusic` | stop the music |
| `Pause`, `Resume` | hold and continue the music; sound effects go on |
| `Playing` | Boolean, read-only: a song is playing (also while paused) |
| `Paused` | Boolean, read-only |
| `CurrentSong` | Long, read-only: the song playing, 0 for none |
| `MusicVolume` | Long 0..64 (default 48, a little under the effects) |
| `MusicEnabled` | Boolean: False silences the music but lets it run on (a game's "music off" switch) |
| `Loop` | Boolean (default True): start again at the end of the song; False = stop at the end |
| `SongEnded` | Long, read-only: how many times the song reached its end since `PlayMusic`; works with `Loop` on, so a game can change tune when it changes |

### Where the music is

| Member | What it does |
|---|---|
| `Position` | Long: the position in the order list; setting it jumps there (row 0) |
| `Row` | Long: the row playing (0 to 63); setting it jumps to that row |
| `Pattern` | Long, read-only: the pattern at the current position |
| `Tick` | Long, read-only: the tick within the row |
| `JumpTo position [, row]` | jump there now |
| `Speed` | Long: ticks per row (1 to 31) |
| `Tempo` | Long: beats per minute (32 to 255) |
| `Mute(channel)` | Boolean, read/write: silence a channel |
| `Solo channel` | only this channel sounds; `Solo -1` brings all back (and clears every mute) |
| `ChannelVolume(channel)` | Long, read-only: the channel's volume now, after effects |
| `ChannelVU(channel)` | Long, read-only: its loudest level over the last chunk (0..64): a VU meter |
| `ChannelNote(channel)`, `ChannelSample(channel)` | Long, read-only: the last note and sample started on it |
| `ChannelPos(channel)` | Long, read-only: how far into its sample the channel is, in bytes; -1 when silent |
| `Scope(channel, n)` | a Long array of the channel's last n output samples (-128..127, n up to 1024): an oscilloscope. Channel -1 = the mixed output (-32768..32767) |
| `Scopes(n [, channels])` | every channel's `Scope` in one array: channel c starts at c x n |
| `State()` | a Long array (0 To 55) with the whole play state (below) |

These reads are cheap and never wait for the mixer; the values are at most one chunk of sound
(40 ms) old. Each call to a member still costs a little, so in a game read what you need
once a frame with `State()`:

| `State()` index | Value |
|---|---|
| 0, 1 | Playing, Paused (True is -1) |
| 2 to 8 | Position, Row, Pattern, Tick, Speed, Tempo, SongEnded |
| 9, 10, 11 | CurrentSong, Channels, CpuLoad |
| 12 to 15 | reserved |
| 16 + c x 5 ... | for channel c: VU, note, sample, volume, ChannelPos |

*Listing 16.5* (`examples/book/ch16-audio/listing-16-05.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim au As Audio, v As Long, st() As Long, sc() As Long, s As Long, i As Long, peak As Long
    Set au = CreateObject("Boing.Audio")
    au.Open "manual"
    ' an effect in the amiga3d style: three tones in one 8-bit buffer
    au.SfxDefine 2, 2400, 48, 20                 ' id 2: 2400 samples, volume 48, priority 20
    au.SfxTone 2, 0, 800, 523, 523, 90, 100      ' C
    au.SfxTone 2, 800, 800, 659, 659, 90, 100    ' E
    au.SfxTone 2, 1600, 800, 784, 784, 90, 200   ' G
    v = au.Sfx(2)
    Print "Sfx voice"; v; " sound number"; au.SfxSound(2); " length"; au.SoundLength(au.SfxSound(2))

    ' a one-row song so there is music to watch
    s = au.NewSong(4)
    au.SampleLength(s, 1) = 32
    For i = 0 To 31: au.SampleData(s, 1, i) = IIf(i < 16, 100, -100): Next i
    au.SampleLoopLength(s, 1) = 32
    au.SampleVolume(s, 1) = 64
    au.SetCell s, 0, 0, 0, au.NoteFromName("A-2"), 1, 0, 0
    au.PlayMusic s
    au.Render 2205
    st = au.State()                              ' everything at once: one call a frame
    Print "playing "; st(0) <> 0; ", position"; st(2); " row"; st(3); " speed"; st(6); " tempo"; st(7)
    Print "channel 0: note "; au.NoteName(st(17)); ", sample"; st(18); ", volume"; st(19)
    sc = au.Scope(0, 64)                         ' the last 64 output samples of channel 0
    For i = 0 To 63
        If Abs(sc(i)) > peak Then peak = Abs(sc(i))
    Next i
    Print "scope:"; UBound(sc) + 1; "samples, peak"; peak
End Sub
```

```output
Sfx voice 1  sound number 1  length 2400 
playing True, position 0  row 0  speed 6  tempo 125 
channel 0: note A-2, sample 1 , volume 64 
scope: 64 samples, peak 100 
```

### Live playing

These play notes immediately, for a tracker's keyboard, step-through, or a jingle.

| Member | What it does |
|---|---|
| `PlayNote channel, note, sample [, volume [, effect, param]]` | play a note of a sample of the current song on a music channel now, with an effect if you like. Works while the music is stopped; the song's own next note on that channel replaces it |
| `PlayRow song, pattern, row` | play one row of a pattern (all channels) now, without starting the song |
| `NoteOff channel` | silence a channel |
| `EditSong` | Long: the song `PlayNote` uses when no song is playing (default: the last one loaded or played) |

## Editing songs

A song is made of **samples** (the instruments, 1 to 31), **patterns** (numbered from 0,
each 64 rows of one cell per channel), and the **order list**, which says which pattern plays
at each position. You can build a song from nothing or change a loaded one, also while it is
playing: changes are heard straight away. The Riffwright tracker in the examples is built on
these members.

All of them take the song number first.

### The song

| Member | What it does |
|---|---|
| `SongName(song)` | String, read/write (up to 20 characters) |
| `Channels(song)` | Long, read-only |
| `SongSpeed(song)`, `SongTempo(song)` | Long, read/write: the speed and tempo `PlayMusic` starts with (6 and 125 normally) |
| `SongLength(song)` | Long 1..128, read/write: how many positions of the order list are used |
| `SongRestart(song)` | Long 0..127, read/write: the restart position stored in the file (127 = none) |
| `Order(song, position)` | Long, read/write: the pattern at a position (0..127) |
| `PatternCount(song)` | Long, read-only: how many patterns are stored |
| `AddPattern(song)` | add an empty pattern; returns its number |
| `ClearPattern song, pattern` | empty a pattern |
| `CopyPattern song, from, to` | copy a pattern over another |

### Cells

A cell holds a note, a sample number, an effect (0 to 15) and an effect parameter (0 to 255).

| Member | What it does |
|---|---|
| `CellNote(song, pattern, row, channel)` | Long, read/write: 0 or 1..36 |
| `CellPeriod(song, pattern, row, channel)` | Long, read/write: the raw Amiga period (0 = none), for pitches between the notes |
| `CellSample(song, pattern, row, channel)` | Long, read/write: 0..31 |
| `CellEffect(song, pattern, row, channel)` | Long, read/write: 0..15 |
| `CellParam(song, pattern, row, channel)` | Long, read/write: 0..255 |
| `Cell(song, pattern, row, channel)` | Long, read/write: all four packed into one number, note x &H1000000 + sample x &H10000 + effect x &H100 + param (copy and paste in one call) |
| `SetCell song, pattern, row, channel, note, sample, effect, param` | all four at once |
| `NoteName(note)`, `NoteFromName(name)` | "C-2" and back |
| `NotePeriod(note [, finetune])` | the Amiga period of a note |

### Samples

| Member | What it does |
|---|---|
| `SampleName(song, s)` | String, read/write (up to 22 characters) |
| `SampleLength(song, s)` | Long, read/write: bytes (even, up to 131070); making it longer adds silence |
| `SampleVolume(song, s)` | Long 0..64, read/write |
| `SampleFinetune(song, s)` | Long -8..7, read/write |
| `SampleLoopStart(song, s)`, `SampleLoopLength(song, s)` | Long, read/write, in bytes (a loop length of 0 or 2 = no loop) |
| `SampleData(song, s, index)` | Long -128..127, read/write: one byte |
| `SetSampleBytes song, s, bytes() [, n]` | set the whole sample from an array: Byte (as stored: 128..255 mean -128..-1) or Integer/Long (-128..127); the length becomes n (default: the whole array) |
| `GetSampleBytes(song, s)` | the sample as a Byte array (Empty if it is empty) |
| `LoadSample song, s, path` | load an 8SVX or WAV file as sample s (converted to 8-bit mono). For raw data use `LoadSound` and `SetSampleFromSound` |
| `SetSampleFromSound song, s, sound` | use a sound as sample s |

Changing a sample's data cuts any note that is playing it.

*Listing 16.6* (`examples/book/ch16-audio/listing-16-06.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim au As Audio, s As Long, snd As Long, b() As Byte, w(0 To 7) As Integer, i As Long, k As Variant
    Set au = CreateObject("Boing.Audio")
    au.Open "manual"
    s = au.NewSong()
    snd = au.SynthTone(50, 440, 440)
    au.SetSampleFromSound s, 1, snd               ' a synthesised tone as instrument 1
    Print "sample 1:"; au.SampleLength(s, 1); "bytes"
    For i = 0 To 7: w(i) = i * 16 - 64: Next i
    au.SetSampleBytes s, 2, w                     ' instrument 2 from an Integer array
    b = au.GetSampleBytes(s, 2)
    Print "sample 2:"; au.SampleLength(s, 2); "bytes:";
    For i = 0 To UBound(b): Print b(i);: Next i
    Print
    Print "data(2, 0) ="; au.SampleData(s, 2, 0)
    Print "C-1 period"; au.NotePeriod(1); " B-3 period"; au.NotePeriod(36)
    au.PlayNote 0, au.NoteFromName("C-2"), 1, 64  ' a live note on channel 0
    au.Render 1000
    Print "channel 0 note "; au.NoteName(au.ChannelNote(0)); " VU"; au.ChannelVU(0) > 0
    au.NoteOff 0
    On Error Resume Next
    k = au.LoadMusic("nosuch.mod")
    Print "missing file: error"; Err.Number
End Sub
```

```output
sample 1: 1102 bytes
sample 2: 8 bytes: 192  208  224  240  0  16  32  48 
data(2, 0) =-64 
C-1 period 856  B-3 period 113 
channel 0 note C-2 VUTrue
missing file: error 53 
```

### A complete song

This program builds a short four-channel song with a looping square-wave instrument, plays it
once through on the `"manual"` device, then saves it as a module and exports it as a WAV
file:

*Listing 16.7* (`examples/book/ch16-audio/listing-16-07.bas`)

<!-- run -->
```basic
' Build a four-channel song from BASIC, play it, save it and export it as a WAV file
Option Explicit

Sub Main()
    Dim au As Audio, s As Long, i As Long, r As Long, p As Long, t As Long
    Dim melody As Variant
    Set au = CreateObject("Boing.Audio")
    au.Open "manual"

    s = au.NewSong(4)
    au.SongName(s) = "manual tune"
    ' sample 1: one cycle of a square wave, 32 bytes, looped
    au.SampleLength(s, 1) = 32
    For i = 0 To 31
        If i < 16 Then au.SampleData(s, 1, i) = 80 Else au.SampleData(s, 1, i) = -80
    Next i
    au.SampleLoopStart(s, 1) = 0
    au.SampleLoopLength(s, 1) = 32
    au.SampleVolume(s, 1) = 48
    au.SampleName(s, 1) = "square"

    ' pattern 0: a melody on channel 0, every fourth row
    melody = Array("C-2", "E-2", "G-2", "C-3", "G-2", "E-2", "C-2", "---", _
                   "D-2", "F-2", "A-2", "D-3", "A-2", "F-2", "D-2", "---")
    For i = 0 To 15
        If melody(i) <> "---" Then au.SetCell s, 0, i * 4, 0, au.NoteFromName(melody(i)), 1, 0, 0
    Next i
    au.SetCell s, 0, 0, 1, au.NoteFromName("C-1"), 1, &HC, 32   ' a bass note, volume 32 (effect C)
    ' pattern 1: a copy of pattern 0, a fifth higher on the bass
    p = au.AddPattern(s)
    au.CopyPattern s, 0, p
    au.CellNote(s, p, 0, 1) = au.NoteFromName("G-1")
    ' the order list: 0, 1, 0
    au.SongLength(s) = 3
    au.Order(s, 0) = 0: au.Order(s, 1) = 1: au.Order(s, 2) = 0
    Print au.SongName(s); ":"; au.SongLength(s); "positions,"; au.PatternCount(s); "patterns,"; au.Channels(s); "channels"
    Print "cell 0/4/0 is "; au.NoteName(au.CellNote(s, 0, 4, 0)); ", packed &H"; Hex$(au.Cell(s, 0, 4, 0))

    ' play it once through, mixing 0.1 s at a time
    au.Loop = False
    au.PlayMusic s
    t = 0
    Do While au.Playing
        au.Render 2205
        t = t + 1
        If t = 30 Then Print "after 3 s: position"; au.Position; " row"; au.Row; " pattern"; au.Pattern
    Loop
    Print "played"; t / 10; "seconds, ended"; au.SongEnded; "time"
    Print "PCM hash"; au.PcmHash

    au.SaveMusic s, "tune.mod"
    au.RenderToWav s, "tune.wav"
    Print "tune.mod"; FileLen("tune.mod"); "bytes, tune.wav"; FileLen("tune.wav"); "bytes"
    Kill "tune.mod": Kill "tune.wav"
End Sub
```

```output
manual tune: 3 positions, 2 patterns, 4 channels
cell 0/4/0 is E-2, packed &H11010000
after 3 s: position 0  row 25  pattern 0 
played 23.1 seconds, ended 1 time
PCM hash 714887021 
tune.mod 3164 bytes, tune.wav 2031660 bytes
```

## ProTracker support

The player handles the ProTracker effects: 0 arpeggio, 1 and 2 slides, 3 tone portamento,
4 vibrato, 5 and 6 (portamento or vibrato with a volume slide), 7 tremolo, 8 panning (00
left, 80 centre, FF right; not in ProTracker itself), 9 sample offset, A volume slide,
B position jump, C volume, D pattern break, F speed and tempo, and the E commands E1/E2 fine
slides, E4/E7 vibrato and tremolo waveform, E5 finetune, E6 pattern loop, E9 retrigger,
EA/EB fine volume slides, EC note cut, ED note delay and EE pattern delay. E0 (the filter),
E3 (glissando) and EF are ignored. Timing is by tempo (BPM), and samples are not smoothed,
just as on the Amiga.

Music channels are panned the Amiga way: channels 0 and 3 left, 1 and 2 right (and the same
pattern again for 6 and 8 channels), with a quarter of each side mixed into the other, which
is kinder on headphones.

## Sound in a game

Glimmerfield (`examples/glimmerfield`, its `Sound.bas`) is a good model. It keeps the Audio
object in a module-level variable, makes all its effects with `SynthTone` and `SynthNoise`
at start-up, plays its music from a module next to the program, and has M and S keys that set
`MusicEnabled` and `SoundEnabled`. A cut-down version of that module:

*Listing 16.8* (`examples/book/ch16-audio/listing-16-08.bas`)

```basic
Option Explicit

Private au As Audio
Private haveAudio As Boolean
Private song As Long
Private sShoot As Long, sBoom As Long, sThrust As Long
Private vThrust As Long

Public Sub SoundInit(ByVal dir As String)
    On Error GoTo NoAudio
    Set au = CreateObject("Boing.Audio")
    au.Open
    sShoot = au.SynthTone(70, 1400, 500, 26, 1)
    sBoom = au.SynthNoise(700, 60, 9, 5)
    sThrust = au.SynthNoise(400, 30, 12, 0)
    au.SoundLoop(sThrust) = True
    au.MusicVolume = 40
    haveAudio = True
    On Error Resume Next
    song = au.LoadMusic(dir & "game.mod")      ' no music file: play without music
    If Err.Number = 0 Then au.PlayMusic song
    Exit Sub
NoAudio:
    haveAudio = False
End Sub

Public Sub SoundShoot()
    If haveAudio Then au.PlaySound sShoot, 40
End Sub

Public Sub SoundBoom()
    If haveAudio Then au.PlaySoundPri sBoom, 10, 64     ' more important than shots
End Sub

' call every frame with the thrust key's state: a looping engine noise
Public Sub SoundThrust(ByVal on_ As Boolean)
    If Not haveAudio Then Exit Sub
    If on_ And vThrust = 0 Then vThrust = au.PlaySound(sThrust, 30)
    If Not on_ And vThrust <> 0 Then au.StopVoice vThrust: vThrust = 0
End Sub

Public Sub SoundMusicSwitch()
    If haveAudio Then au.MusicEnabled = Not au.MusicEnabled
End Sub

Sub Main()
    SoundInit "PROGDIR:"
    SoundShoot
    SoundBoom
End Sub
```

## Speed

The mixer costs little: on the emulated sam460ex, Glimmerfield's four-channel music at 22050 Hz
took 0.9 % of the processor, and each effect voice costs about as much as a music channel.
Calls from BASIC are what cost time, especially in the interpreter, so keep the Audio object in
a module-level variable and read the play state once a frame with `State()` instead of
several separate properties.

## Summary

- `CreateObject("Boing.Audio")` gives the one mixer; it opens AHI by itself on AmigaOS 4, and
  every call still works when there is no sound device.
- `LoadMusic` and `PlayMusic` play MOD files; `MusicEnabled`, `MusicVolume`, `Loop` and
  `SongEnded` cover a game's needs.
- `LoadSound`, `CreateSound`, `SynthTone` and `SynthNoise` make sounds; `PlaySound` and
  `PlaySoundPri` play them on 8 voices.
- Songs can be built and edited cell by cell, saved as modules and rendered to WAV.
- The `"manual"` device, `Render` and `PcmHash` make sound code testable without hardware.

See also: [Graphics](14-graphics.md), [Engine3D](15-engine3d.md), [Files](10-files.md).
