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
