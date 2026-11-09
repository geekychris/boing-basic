' Harbour Crane host test: games whose state hashes must equal the C original's
' (examples/harbour_crane/tools/trace.sh prints the same lines)
Option Explicit

Private Sub Play(ByVal seed As Long, ByVal level As Long, ByVal maxT As Long, ByVal wobble As Boolean)
    Dim t As Long, s As Long, inp As Long, w As String
    s = 11
    HcNewGame seed, level
    Do While t < maxT And hcOver = 0 And hcWon = 0
        If wobble Then
            If t Mod 7 = 0 Then inp = A3Rand(s) Mod 32
        Else
            inp = HcBot()
        End If
        HcTick inp
        hcNEv = 0
        t = t + 1
    Loop
    If wobble Then w = " random input"
    Print "seed " & seed & " level " & level & w & ", " & t & " ticks: level " & hcLevel & " score " & hcScore & _
          " loaded " & hcTotalLoaded & " lost " & hcLost & " dents " & hcDents & " hash " & Hex8(HcStateHash())
End Sub

Sub Main()
    HcInit
    Play 1234, 1, 15000, False
    Play 4, 4, 9000, False
    Play 8, 7, 6000, False
    Play 2, 3, 2000, True
End Sub
