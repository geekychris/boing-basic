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
