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
