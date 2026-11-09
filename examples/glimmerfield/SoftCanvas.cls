' Glimmerfield - a software canvas: the Canvas control's drawing methods on a
' 400 x 300 framebuffer of RGB Longs, all in BASIC. It lets the renderer run
' (and be timed) in the console bench, on any platform, and its Hash makes
' the drawing comparable between the VM and native builds.
Option Explicit

Private Const W As Long = 400
Private Const H As Long = 300
Private Const NPIX As Long = 120000

Private px(0 To 119999) As Long       ' back buffer (drawn into)
Private shown(0 To 119999) As Long    ' front buffer (Flip copies into it)
Public Flips As Long

Public Sub Cls(ByVal c As Long)
    Dim i As Long
    For i = 0 To NPIX - 1
        px(i) = c
    Next i
End Sub

Public Sub PSet(ByVal x As Long, ByVal y As Long, ByVal c As Long)
    If x >= 0 And x < W And y >= 0 And y < H Then px(y * W + x) = c
End Sub

Public Sub Line(ByVal x1 As Long, ByVal y1 As Long, ByVal x2 As Long, ByVal y2 As Long, ByVal c As Long)
    Dim dx As Long, dy As Long, sx As Long, sy As Long, e As Long, e2 As Long
    dx = Abs(x2 - x1)
    dy = -Abs(y2 - y1)
    If x1 < x2 Then sx = 1 Else sx = -1
    If y1 < y2 Then sy = 1 Else sy = -1
    e = dx + dy
    Do
        If x1 >= 0 And x1 < W And y1 >= 0 And y1 < H Then px(y1 * W + x1) = c
        If x1 = x2 And y1 = y2 Then Exit Do
        e2 = 2 * e
        If e2 >= dy Then
            e = e + dy
            x1 = x1 + sx
        End If
        If e2 <= dx Then
            e = e + dx
            y1 = y1 + sy
        End If
    Loop
End Sub

Public Sub Box(ByVal x As Long, ByVal y As Long, ByVal bw As Long, ByVal bh As Long, ByVal c As Long)
    Dim i As Long, j As Long, x2 As Long, y2 As Long
    x2 = x + bw - 1
    y2 = y + bh - 1
    If x < 0 Then x = 0
    If y < 0 Then y = 0
    If x2 >= W Then x2 = W - 1
    If y2 >= H Then y2 = H - 1
    For j = y To y2
        For i = x To x2
            px(j * W + i) = c
        Next i
    Next j
End Sub

Public Sub Circle(ByVal cx As Long, ByVal cy As Long, ByVal r As Long, ByVal c As Long, Optional ByVal filled As Boolean = False)
    Dim x As Long, y As Long, e As Long
    x = r
    y = 0
    e = 1 - r
    Do While x >= y
        If filled Then
            Box cx - x, cy + y, 2 * x + 1, 1, c
            Box cx - x, cy - y, 2 * x + 1, 1, c
            Box cx - y, cy + x, 2 * y + 1, 1, c
            Box cx - y, cy - x, 2 * y + 1, 1, c
        End If
        PSet cx + x, cy + y, c
        PSet cx + y, cy + x, c
        PSet cx - y, cy + x, c
        PSet cx - x, cy + y, c
        PSet cx - x, cy - y, c
        PSet cx - y, cy - x, c
        PSet cx + y, cy - x, c
        PSet cx + x, cy - y, c
        y = y + 1
        If e < 0 Then
            e = e + 2 * y + 1
        Else
            x = x - 1
            e = e + 2 * (y - x) + 1
        End If
    Loop
End Sub

Public Function TextWidth(ByVal s As String) As Long
    TextWidth = Len(s) * 6
End Function

' many points in one call (the Canvas control's PSetMany)
Public Sub PSetMany(xs() As Long, ys() As Long, cs() As Long, ByVal n As Long, Optional ByVal size As Long = 1)
    Dim i As Long, x As Long, y As Long
    For i = 0 To n - 1
        x = xs(i)
        y = ys(i)
        If size > 1 Then
            Box x, y, size, size, cs(i)
        ElseIf x >= 0 And x < W And y >= 0 And y < H Then
            px(y * W + x) = cs(i)
        End If
    Next i
End Sub

' a closed polygon of the first n points; filled with the even-odd rule at pixel centres
Public Sub Polygon(xs() As Long, ys() As Long, ByVal n As Long, ByVal c As Long, Optional ByVal filled As Boolean = False)
    Dim i As Long, j As Long, k As Long, y As Long, ymin As Long, ymax As Long, nx As Long, t As Long
    Dim xb(0 To 15) As Long, num As Long, den As Long
    If Not filled Then
        For i = 0 To n - 1
            j = (i + 1) Mod n
            Line xs(i), ys(i), xs(j), ys(j), c
        Next i
        Exit Sub
    End If
    ymin = ys(0)
    ymax = ys(0)
    For i = 1 To n - 1
        If ys(i) < ymin Then ymin = ys(i)
        If ys(i) > ymax Then ymax = ys(i)
    Next i
    If ymin < 0 Then ymin = 0
    If ymax >= H Then ymax = H - 1
    For y = ymin To ymax
        nx = 0
        j = n - 1
        For i = 0 To n - 1
            If (ys(i) <= y And ys(j) > y) Or (ys(j) <= y And ys(i) > y) Then
                num = (2 * y + 1 - 2 * ys(i)) * (xs(j) - xs(i))
                den = 2 * (ys(j) - ys(i))
                If num >= 0 Then
                    xb(nx) = xs(i) + num \ den
                Else
                    xb(nx) = xs(i) - ((-num + den - 1) \ den)
                End If
                nx = nx + 1
            End If
            j = i
        Next i
        For i = 1 To nx - 1
            k = i
            Do While k > 0
                If xb(k - 1) <= xb(k) Then Exit Do
                t = xb(k): xb(k) = xb(k - 1): xb(k - 1) = t
                k = k - 1
            Loop
        Next i
        For i = 0 To nx - 2 Step 2
            If xb(i + 1) - 1 >= xb(i) Then Box xb(i), y, xb(i + 1) - xb(i), 1, c
        Next i
    Next y
End Sub

' 6-pixel cells; a made-up 5 x 7 pattern per character (a bench, not a font)
Public Sub DrawText(ByVal x As Long, ByVal y As Long, ByVal s As String, ByVal c As Long)
    Dim k As Long, r As Long, b As Long, a As Long, bits As Long
    For k = 1 To Len(s)
        a = Asc(Mid$(s, k, 1))
        If a <> 32 Then
            For r = 0 To 6
                bits = (a * (r + 3) + r * 7) And 31
                For b = 0 To 4
                    If (bits And (16 \ (2 ^ b))) <> 0 Then PSet x + b, y + r, c
                Next b
            Next r
        End If
        x = x + 6
    Next k
End Sub

' "blit": copy the back buffer to the front one
Public Sub Flip()
    Dim i As Long
    For i = 0 To NPIX - 1
        shown(i) = px(i)
    Next i
    Flips = Flips + 1
End Sub

' a hash of the shown picture
Public Function Hash() As Long
    Dim i As Long, hv As Long
    For i = 0 To NPIX - 1 Step 7
        hv = (hv * 31 + (shown(i) And 65535) + shown(i) \ 65536) Mod 1000003
    Next i
    Hash = hv
End Function
