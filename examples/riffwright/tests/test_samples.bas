' Riffwright tests - samples
Option Explicit

Function SV(ByVal i As Long, ByVal j As Long) As Long
    Dim d As Variant, v As Long
    d = smpData(i)
    v = d(j): If v > 127 Then v = v - 256
    SV = v
End Function

Sub Show(ByVal i As Long)
    Print "  ["; SampleText(i); "] len"; smpLen(i); "vol"; smpVol(i); "loop"; smpLoopS(i); smpLoopL(i); _
        " first:"; SV(i, 0); SV(i, 1); SV(i, 2); SV(i, 3); "  "; smpInfo
End Sub

Sub Main()
    Dim i As Long, ok As Boolean, peak As Long
    NewSong 4
    Check "16-bit stereo WAV", LoadSampleFile(1, "ref/tone16s.wav")
    Show 1
    Check "8-bit mono WAV", LoadSampleFile(2, "ref/tone8m.wav")
    Show 2
    Check "8SVX", LoadSampleFile(3, "ref/wave.8svx")
    Show 3
    Check "8SVX Fibonacci", LoadSampleFile(4, "ref/wavefib.8svx")
    Show 4
    peak = 0
    For i = 0 To smpLen(4) - 1
        If Abs(SV(4, i) - SV(3, i)) > peak Then peak = Abs(SV(4, i) - SV(3, i))
    Next i
    Print "  Fibonacci vs plain, largest difference:"; peak
    Check "raw", LoadSampleFile(5, "ref/ramp.raw")
    Show 5
    ' save and load back in each format
    SaveSampleFile 3, "t.8svx", "8svx"
    LoadSampleFile 6, "t.8svx"
    Show 6
    Check "8SVX round trip", smpLen(6) = smpLen(3) And SV(6, 77) = SV(3, 77) And smpLoopS(6) = 300 And smpVol(6) = 32
    SaveSampleFile 2, "t.wav", "wav"
    LoadSampleFile 7, "t.wav"
    Check "WAV round trip", smpLen(7) = smpLen(2) And SV(7, 10) = SV(2, 10)
    SaveSampleFile 5, "t.raw", "raw"
    Check "raw round trip", CompareFiles("t.raw", "ref/ramp.raw") = "same"
    Kill "t.8svx": Kill "t.wav": Kill "t.raw"
    ' operations
    Check "reverse", SmpReverse(5)
    Print "  reversed first:"; SV(5, 0); SV(5, 1); " last:"; SV(5, smpLen(5) - 1)
    Undo
    Print "  undo:"; SV(5, 0); SV(5, 1)
    Check "normalise", SmpNormalise(2)
    peak = 0
    For i = 0 To smpLen(2) - 1
        If Abs(SV(2, i)) > peak Then peak = Abs(SV(2, i))
    Next i
    Print "  peak after normalise:"; peak
    Check "no crop when the loop ends the sample", Not SmpCropToLoop(3)
    EdSampleParams 3, 32, 0, 100, 100
    Check "crop to loop", SmpCropToLoop(3)
    Print "  len after crop:"; smpLen(3)
    Check "missing file refused", Not LoadSampleFile(8, "ref/none.wav")
    Print "  "; smpError
End Sub
