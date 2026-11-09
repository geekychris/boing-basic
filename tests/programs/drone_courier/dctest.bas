' Drone Courier host test: flights whose state hashes must equal the C original's
' (examples/drone_courier/tools/trace.sh prints the same lines)
Option Explicit

Private Sub Play(ByVal seed As Long, ByVal day As Long, ByVal maxT As Long, ByVal wobble As Boolean)
    Dim t As Long, s As Long, inp As Long, w As String
    s = 5
    DcNewGame seed, day
    Do While t < maxT And dcOver = 0 And dcWon = 0
        If wobble Then
            If t Mod 8 = 0 Then inp = A3Rand(s) Mod 32
        Else
            inp = DcBot()
        End If
        DcTick inp
        dcNEv = 0
        t = t + 1
    Loop
    If wobble Then w = " random input"
    Print "seed " & seed & " day " & day & w & ", " & t & " ticks: day " & dcDay & " jobs " & dcJobsDone & _
          " fails " & dcFails & " bumps " & dcBumps & " score " & dcScore & " hash " & Hex8(DcStateHash())
End Sub

Sub Main()
    DcInit
    Play 1234, 1, 9000, False
    Play 3, 2, 5000, False
    Play 55, 4, 5000, False
    Play 9, 3, 1500, True
End Sub
