' blit pixel check (tests-os4/blit/run.sh): a fixed picture, shown once, then the program waits so
' a screenshot of the guest can be compared between builds
Private Sub Form_Load()
    Dim x As Long, y As Long, w As Long, h As Long
    w = view.Width: h = view.Height
    view.Cls
    For y = 0 To h - 1 Step 4
        view.Line 0, y, w - 1, y, RGB(y Mod 256, (y * 3) Mod 256, 255 - (y Mod 256))
    Next
    For x = 0 To w - 1 Step 8
        view.Line x, 0, x, h - 1, RGB(255 - (x Mod 256), x Mod 256, (x * 5) Mod 256)
    Next
    view.FillRect 10, 10, 40, 30, RGB(255, 0, 0)
    view.FillRect w - 50, h - 40, 40, 30, RGB(0, 255, 0)
    view.Circle w \ 2, h \ 2, 40, RGB(255, 255, 0)
    view.PSet 0, 0, RGB(255, 255, 255): view.PSet w - 1, h - 1, RGB(0, 0, 255)
    view.DrawText 60, 60, "BLIT 123", RGB(255, 255, 255)
    view.Flip
    If Command$ <> "" Then view.SavePNG Command$     ' the expected picture (tests-os4/blit/run.sh, on the host)
    Print "picture hash"; view.Hash
End Sub

Private Sub tick_Timer()
    Static n As Long
    n = n + 1
    If n >= 60 Then Print "bye": End        ' 60 x 250 ms
End Sub
