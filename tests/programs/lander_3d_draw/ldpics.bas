' Lander 3D drawing test: the game's frames on an off-screen canvas (no pictures beside
' the test, so the sky is the plain fallback), the state and picture hashes every 250
' frames, then the title, help and score screens.
Option Explicit

Sub Main()
    Dim cv As Object, i As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 640, 512
    DrawInit cv
    GameInit
    SoundInit False
    HsSetup Array("ALDRIN", "ARMSTRNG", "CONRAD", "BEAN", "SHEPARD", "MITCHELL", "SCOTT", "IRWIN"), 400
    HsDefaults
    entryRank = -1
    StartGame MODE_TOUR, 1
    gDemo = True
    For i = 1 To 1500
        If gState = LS_OVER And gStateTimer = 0 Then
            StartGame MODE_TOUR, 1
            gDemo = True
        End If
        GameFrame
        If gWorldChanged Then
            DrawPalette ld.world
            gWorldChanged = False
        End If
        DrawGame
        If i Mod 250 = 0 Then
            Print "frame " & i & ": " & wName(ld.world) & " level " & ld.lvl & " score " & gScore & _
                  " state " & gState & " hash " & Hex8(LdStateHash()) & " picture " & cv.Hash & " polys " & e.NPolys
        End If
    Next i
    DrawHelp 1
    Print "help 1 " & cv.Hash
    DrawHelp 2
    Print "help 2 " & cv.Hash
    DrawScores
    Print "scores " & cv.Hash
    ToTitle
    DrawPalette ld.world
    For i = 1 To 30
        GameFrame
    Next i
    DrawTitle
    Print "title " & cv.Hash
    Print "effects " & sfxCount(SFX_THRUST) & " " & sfxCount(SFX_RCS) & " " & sfxCount(SFX_LAND) & " " & _
          sfxCount(SFX_CRASH) & " " & sfxCount(SFX_FUEL) & " " & sfxCount(SFX_BEEP)
End Sub
