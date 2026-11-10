' palette.bas - a palette of 32 colours edited with the CommonDialog's ShowPalette
' ("boing run palette.bbp --show" opens the requester at once, for a screenshot)
Option Explicit

' a colour from hue (0-360), saturation and brightness (0-1)
Private Function HSV(ByVal h As Double, ByVal s As Double, ByVal v As Double) As Long
    Dim f As Double, p As Double, q As Double, t As Double, r As Double, g As Double, b As Double
    h = (h - 360 * Int(h / 360)) / 60
    f = h - Int(h)
    p = v * (1 - s): q = v * (1 - s * f): t = v * (1 - s * (1 - f))
    Select Case Int(h)
    Case 0: r = v: g = t: b = p
    Case 1: r = q: g = v: b = p
    Case 2: r = p: g = v: b = t
    Case 3: r = p: g = q: b = v
    Case 4: r = t: g = p: b = v
    Case Else: r = v: g = p: b = q
    End Select
    HSV = RGB(CInt(r * 255), CInt(g * 255), CInt(b * 255))
End Function

Private Sub Form_Load()
    Dim i As Integer
    dlg.ColorCount = 32
    For i = 0 To 15                       ' the first row: soft colours round the colour wheel
        dlg.Colors(i) = HSV(i * 22.5, 0.55, 0.95)
    Next
    For i = 0 To 7                        ' the second row: deeper colours, then greys
        dlg.Colors(16 + i) = HSV(i * 45 + 10, 0.8, 0.6)
        dlg.Colors(24 + i) = RGB(i * 36, i * 36, i * 36)
    Next
    dlg.ColorIndex = 9                    ' the requester starts on colour 9
    If Command() = "--show" Then startUp.Enabled = True
End Sub

' "--show": open the requester once the window is on the screen
Private Sub startUp_Timer()
    startUp.Enabled = False
    pick_Click
End Sub

Private Sub pick_Click()
    Dim c As Long
    dlg.ShowPalette
    If dlg.Cancelled Then sb.Text = "Cancelled": Exit Sub
    c = dlg.Colors(dlg.ColorIndex)
    chosen.Caption = "Colour " & dlg.ColorIndex & ": red " & (c And 255) & ", green " & _
                     ((c \ 256) And 255) & ", blue " & ((c \ 65536) And 255)
    sb.Text = "Picked colour " & dlg.ColorIndex
End Sub

Private Sub quit_Click()
    Unload Me
End Sub
