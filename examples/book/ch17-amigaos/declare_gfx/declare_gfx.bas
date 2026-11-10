' declare_gfx.bas - draws an animation in a window opened and painted entirely through
' Declare'd OS functions (bindings/intuition.bi, graphics.bi, exec.bi) and the pointer
' builtins: OpenWindowTagList + TagList, PeekL/PeekB into struct Window, SetRPAttrsA,
' RectFillColor, Move/Draw, WritePixelColor, Text, GetMsg/ReplyMsg on the window's port.
' It doubles as a test of the bindings: it prints PASS and the cost of a call.
'
'   boing run declare_gfx.bbp [--frames N] [--wait]
'     --frames N   frames to draw (default 200)
'     --wait       keep the window open until its close gadget is clicked
' Ctrl-C raises error 18 (User interrupt): the handler closes the window, which the runtime
' does not know about (it was opened through Declare).
Option Explicit

' struct Window offsets (AmigaOS keeps the 68k layout, 2-byte packed)
Private Const WIN_RPORT As Long = 50
Private Const WIN_BORDERLEFT As Long = 54
Private Const WIN_BORDERTOP As Long = 55
Private Const WIN_USERPORT As Long = 86
' struct IntuiMessage: Class at 20 (after the 20-byte Message)
Private Const IM_CLASS As Long = 20

Private Const W As Long = 320
Private Const H As Long = 200

Private win As Long, rp As Long, bx As Long, by As Long

Private Function Argb(ByVal r As Long, ByVal g As Long, ByVal b As Long) As Long
    ' 0xFFRRGGBB without overflowing a Long: &HFF000000 is negative
    Argb = &HFF000000 Or (r * 65536) Or (g * 256) Or b
End Function

Private Sub Box(ByVal x As Long, ByVal y As Long, ByVal x2 As Long, ByVal y2 As Long, ByVal c As Long)
    RectFillColor rp, bx + x, by + y, bx + x2, by + y2, c
End Sub

Private Sub Pen(ByVal c As Long)
    Dim t As Long
    t = TagList(RPTAG_APenColor, c)
    SetRPAttrsA rp, t
    FreeTagList t
End Sub

' True if the close gadget was clicked (drains the window's message port)
Private Function CloseClicked() As Boolean
    Dim port As Long, msg As Long
    port = PeekL(win + WIN_USERPORT)
    Do
        msg = GetMsg(port)
        If msg = 0 Then Exit Do
        If PeekL(msg + IM_CLASS) = IDCMP_CLOSEWINDOW Then CloseClicked = True
        ReplyMsg msg
    Loop
End Function

Sub Main()
    Dim args() As String, i As Long, frames As Long, waitClose As Boolean
    Dim tags As Long, f As Long, x As Long, y As Long, dx As Long, dy As Long, k As Long
    Dim t0 As Double, ms As Double, calls As Long, s As String
    Dim sx(0 To 39) As Long, sy(0 To 39) As Long

    frames = 200
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        If LCase$(args(i)) = "--frames" And i < UBound(args) Then frames = CLng(args(i + 1))
        If LCase$(args(i)) = "--wait" Then waitClose = True
    Next i

    tags = TagList(WA_Title, "Boing BASIC: Declare'd graphics", WA_Left, 60, WA_Top, 60, _
                   WA_InnerWidth, W, WA_InnerHeight, H, WA_DragBar, 1, WA_DepthGadget, 1, _
                   WA_CloseGadget, 1, WA_Activate, 0, WA_IDCMP, IDCMP_CLOSEWINDOW)
    win = OpenWindowTagList(0, tags)
    FreeTagList tags
    If win = 0 Then
        Print "FAIL: OpenWindowTagList returned 0"
        Exit Sub
    End If
    On Error GoTo closeit
    rp = PeekL(win + WIN_RPORT)
    bx = PeekB(win + WIN_BORDERLEFT)
    by = PeekB(win + WIN_BORDERTOP)
    Print "window open: border "; bx; by; " rastport ok "; (rp <> 0)

    For k = 0 To 39
        sx(k) = (k * 73 + 11) Mod W
        sy(k) = (k * 37 + 5) Mod H
    Next k
    x = 40: y = 30: dx = 3: dy = 2
    t0 = TimerMs()
    For f = 1 To frames
        Box 0, 0, W - 1, H - 1, Argb(8, 10, 30)
        For k = 0 To 39                          ' a drifting starfield
            sx(k) = (sx(k) + 1 + (k Mod 3)) Mod W
            WritePixelColor rp, bx + sx(k), by + sy(k), Argb(160, 170, 220)
        Next k
        x = x + dx: y = y + dy                   ' a bouncing box with a cross
        If x < 0 Or x > W - 40 Then dx = -dx: x = x + 2 * dx
        If y < 12 Or y > H - 40 Then dy = -dy: y = y + 2 * dy
        Box x, y, x + 39, y + 39, Argb(220, 60, 60)
        Pen Argb(255, 255, 255)
        Move rp, bx + x, by + y
        Draw rp, bx + x + 39, by + y + 39
        Move rp, bx + x + 39, by + y
        Draw rp, bx + x, by + y + 39
        s = "FRAME " & CStr(f)
        Move rp, bx + 4, by + 10
        Text rp, s, Len(s)
        calls = calls + 1 + 40 + 1 + 1 + 4 + 2 + 1
        If CloseClicked() Then Exit For
    Next f
    ms = TimerMs() - t0
    If f > frames Then f = frames
    Print "frames "; f; " ("; Format$(ms / f, "0.00"); " ms/frame, "; _
          Format$(ms * 1000# / calls, "0.0"); " us per OS call)"
    Do While waitClose
        If CloseClicked() Then Exit Do
        Sleep 50
    Loop
    CloseWindow win
    win = 0
    Print "PASS"
    Exit Sub
closeit:
    ' Ctrl-C (error 18) or any other error: close the window, then report it
    If win <> 0 Then CloseWindow win: win = 0
    If Err.Number = 18 Then Print "break: window closed" Else Print "error"; Err.Number; Err.Description
End Sub
