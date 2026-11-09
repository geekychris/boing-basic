' Lander 3D host test: the lines examples/lander_3d_bb/tools/trace.sh prints from the C
' original (amiga_mcp's ld_core.c) must come out the same.
Option Explicit

Private Sub ShowLevel()
    Dim k As Long
    Print "level w" & ld.world & " l" & ld.lvl & " seed " & ld.seed & " terrain " & Hex8(LdTerrainHash()) & _
          " start " & ld.px & " " & ld.py & " " & ld.pz & " v " & ld.vx & " " & ld.vy & " " & ld.vz & " fuel " & ld.fuel
    For k = 0 To 2
        Print " pad" & k & " " & padX(k) & " " & padZ(k) & " r " & padR(k) & " y " & padY(k) & " x" & padMult(k)
    Next k
End Sub

' mode 0 autopilot, 1 scripted pilot (assist), 2 scripted pilot (no assist)
Private Sub Fly(ByVal world As Long, ByVal lv As Long, ByVal seed As Long, ByVal mode As Long, ByVal maxT As Long)
    Dim t As Long, e As Long, nev As Long, r As Long
    LdNewLevel world, lv, seed, False
    If mode = 2 Then ld.assist = 0
    ShowLevel
    t = 0
    Do While t < maxT And ld.outcome = 0
        If mode = 0 Then
            LdAutopilot
        Else
            r = A3Hash(AddW(MulW(t \ 37, &H9E3779B1), seed))
            inThr = (r And 15) * 4369
            Select Case r And &H30
                Case &H10: inPitch = FONE
                Case &H20: inPitch = -FONE
                Case Else: inPitch = 0
            End Select
            Select Case r And &HC0
                Case &H40: inRoll = FONE
                Case &H80: inRoll = -FONE
                Case Else: inRoll = 0
            End Select
            If ld.vy < -393216 Then inThr = FONE
        End If
        LdStep
        e = LdPopEvent()
        Do While e <> LDE_NONE
            nev = nev * 7 + e
            e = LdPopEvent()
        Loop
        If t Mod 1000 = 999 Then Print " t" & (t + 1) & " hash " & Hex8(LdStateHash())
        t = t + 1
    Loop
    Print "end t" & t & " outcome " & ld.outcome & " score " & ld.rScore & " soft " & ld.rSoft & " fb " & ld.rFuelBonus & _
          " vs " & ld.rVs & " hs " & ld.rHs & " tilt " & ld.rTilt & " ev " & nev & " agl " & LdAgl() & _
          " tiltnow " & LdTilt() & " near " & LdNearestPad(False) & " hash " & Hex8(LdStateHash())
End Sub

Private Sub Probe(ByVal world As Long, ByVal lv As Long, ByVal seed As Long)
    LdNewLevel world, lv, seed, True
    Print "probe w" & world & " l" & lv & " seed " & seed & " used " & ld.probeUsed & " outcome " & ld.probeOutcome & _
          " fuel " & ld.fuel & " max " & ld.fuelMax
End Sub

Sub Main()
    Dim w As Long, lv As Long, k As Long, lvs As Variant
    LdInit
    For w = 0 To 2
        For lv = 1 To 10 Step 3
            LdLevelParams w, lv
            Print "params w" & w & " l" & lv & " " & ld.pFuel & " " & ld.pStartAlt & " " & ld.pStartH & " " & _
                  ld.pStartDist & " " & ld.pPadScale & " " & ld.pWind
        Next lv
    Next w
    Fly 0, 1, 1018, 0, 40000
    lvs = Array(1, 3, 7)
    For w = 0 To 2
        For k = 0 To 2
            Fly w, lvs(k), 1000 + w * 10 + lvs(k), 0, 40000
        Next k
    Next w
    Fly 0, 2, 2026, 1, 40000
    Fly 1, 1, 2027, 1, 40000
    Fly 2, 1, 2028, 2, 40000
    Fly 1, 5, 31337, 2, 40000
    Probe 0, 1, 2026
    Probe 1, 4, 77
    Probe 2, 2, 5
    SoundInit False
    Print "sounds " & Hex8(sndSum)
End Sub
