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
