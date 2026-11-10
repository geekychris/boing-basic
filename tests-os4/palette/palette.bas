' palette.bas - CommonDialog.ShowPalette called from BASIC (a Timer event, as the manual's
' example), six times: closed alternately with Return (kept) and Esc (cancelled) by
' RAM:bbt/key_inject, which Form_Load starts. TAP lines and PASS/FAIL on stdout.
Option Explicit
Dim n As Integer, fails As Integer, before(31) As Long

Private Sub Check(ByVal ok As Boolean, ByVal what As String)
    n = n + 1
    If ok Then Print "ok "; n; " - "; what Else Print "not ok "; n; " - "; what: fails = fails + 1
End Sub

Private Sub Form_Load()
    Dim i As Integer
    dlg.ColorCount = 32
    For i = 0 To 31
        dlg.Colors(i) = RGB((i * 37) Mod 256, (i * 91) Mod 256, (i * 53) Mod 256)
        before(i) = dlg.Colors(i)
    Next
    dlg.ColorIndex = 9
    Shell "run >NIL: RAM:bbt/key_inject ""Palette test"" 6 0x44 0x45", 0
    startUp.Enabled = True
End Sub

Private Function Same() As Boolean
    Dim i As Integer
    Same = True
    For i = 0 To 31
        If dlg.Colors(i) <> before(i) Then Same = False
    Next
End Function

Private Sub startUp_Timer()
    Dim k As Integer
    startUp.Enabled = False
    For k = 1 To 6
        dlg.ShowPalette
        If k Mod 2 = 1 Then
            Check Not dlg.Cancelled And dlg.ColorIndex = 9 And Same(), "ShowPalette " & k & " closed with Return: colours and ColorIndex kept"
        Else
            Check dlg.Cancelled And Same(), "ShowPalette " & k & " closed with Esc: Cancelled"
        End If
        sb.Text = "round " & k
    Next
    Check dlg.ColorCount = 32, "ColorCount still 32"
    Print IIf(fails = 0, "PASS", "FAIL")
    Unload Me
End Sub
