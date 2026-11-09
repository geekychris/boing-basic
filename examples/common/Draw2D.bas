' Draw2D - the amiga3d engine's 2D calls on one Canvas (gcv), in the games' 320 x 256
' coordinates: 32 pens (12-bit Amiga colours), filled rectangles by corners,
' text with a shadow, centred text and big text (cached as scaled images).
' The Canvas's own font is 6 x 9 (the Amiga's topaz is 8 x 8), so text is centred
' by its real width; y is the text's baseline, as g_text has it.
Option Explicit

Public pen(0 To 31) As Long          ' VB colours of the 32 pens
' the Canvas everything draws on (set once: on the OS4 guest a procedure with an Object
' parameter or local costs ~20 us a call, a module-level one nothing)
Public gcv As Object
Public Const G_W As Long = 320
Public Const G_H As Long = 256

Private bigKey As New Collection     ' "scale|pen|text" -> image number
Private bigCount As Long

' pens from 12-bit Amiga colours (&HRGB)
Public Sub GfxPalette(cols As Variant)
    Dim i As Long, c As Long
    For i = 0 To 31
        c = cols(i)
        pen(i) = RGB(((c \ 256) And 15) * 17, ((c \ 16) And 15) * 17, (c And 15) * 17)
    Next i
End Sub

Public Function Rgb12(ByVal c As Long) As Long
    Rgb12 = RGB(((c \ 256) And 15) * 17, ((c \ 16) And 15) * 17, (c And 15) * 17)
End Function

' a filled rectangle with corners (x0, y0) and (x1, y1), inclusive
Public Sub GRect(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal p As Long)
    If x1 < x0 Or y1 < y0 Then Exit Sub
    gcv.Box x0, y0, x1 - x0 + 1, y1 - y0 + 1, pen(p)
End Sub

' a box: filled, with an edge
Public Sub GBox(ByVal x0 As Long, ByVal y0 As Long, ByVal x1 As Long, ByVal y1 As Long, ByVal fillPen As Long, ByVal edgePen As Long)
    gcv.Box x0, y0, x1 - x0 + 1, y1 - y0 + 1, pen(fillPen)
    gcv.Rect x0, y0, x1 - x0 + 1, y1 - y0 + 1, pen(edgePen)
End Sub

Public Sub GText(ByVal x As Long, ByVal y As Long, ByVal p As Long, ByVal s As String)
    gcv.DrawText x, y - 7, s, pen(p)
End Sub

Public Sub GTextShadow(ByVal x As Long, ByVal y As Long, ByVal p As Long, ByVal s As String)
    gcv.DrawText x + 1, y - 6, s, pen(0)
    gcv.DrawText x, y - 7, s, pen(p)
End Sub

Public Sub GTextCentre(ByVal y As Long, ByVal p As Long, ByVal s As String)
    GTextShadow (G_W - gcv.TextWidth(s)) \ 2, y, p, s
End Sub

Public Function GTextWidth(ByVal s As String) As Long
    GTextWidth = gcv.TextWidth(s)
End Function

' big text, each of the font's pixels sc x sc; y is the top. Made once per text,
' pen and scale into an image, then copied.
Public Sub GTextBig(ByVal x As Long, ByVal y As Long, ByVal p As Long, ByVal s As String, ByVal sc As Long)
    Dim key As String, img As Long
    key = sc & "|" & p & "|" & s
    On Error Resume Next
    img = bigKey(key)
    On Error GoTo 0
    If img = 0 Then
        img = MakeBig(s, pen(p), sc)
        bigKey.Add img, key
    End If
    gcv.DrawImage img, x, y
End Sub

Public Function GTextBigWidth(ByVal s As String, ByVal sc As Long) As Long
    GTextBigWidth = gcv.TextWidth(s) * sc
End Function

' centred big text
Public Sub GTextBigCentre(ByVal y As Long, ByVal p As Long, ByVal s As String, ByVal sc As Long)
    GTextBig (G_W - gcv.TextWidth(s) * sc) \ 2, y, p, s, sc
End Sub

Private Function MakeBig(ByVal s As String, ByVal col As Long, ByVal sc As Long) As Long
    Dim small As Long, big As Long, w As Long, h As Long, x As Long, y As Long, x2 As Long
    w = gcv.TextWidth(s)
    h = gcv.TextHeight(s)
    small = gcv.CreateImage(w, h)
    big = gcv.CreateImage(w * sc, h * sc)
    If col = 0 Then col = &H10101        ' (black would read as see-through)
    gcv.SetTarget small
    gcv.DrawText 0, 0, s, vbWhite
    For y = 0 To h - 1
        x = 0
        Do While x < w
            If gcv.Point(x, y) <> -1 And gcv.Point(x, y) <> 0 Then
                x2 = x
                Do While x2 + 1 < w
                    If gcv.Point(x2 + 1, y) = -1 Or gcv.Point(x2 + 1, y) = 0 Then Exit Do
                    x2 = x2 + 1
                Loop
                gcv.SetTarget big
                gcv.Box x * sc, y * sc, (x2 - x + 1) * sc, sc, col
                gcv.SetTarget small
                x = x2 + 1
            Else
                x = x + 1
            End If
        Loop
    Next y
    gcv.SetTarget 0
    gcv.FreeImage small
    bigCount = bigCount + 1
    MakeBig = big
End Function
