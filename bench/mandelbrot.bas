' Mandelbrot set as text
Dim x As Long, y As Long, i As Long, n As Long, w As Long, h As Long, line As String, total As Long
Dim cr As Double, ci As Double, zr As Double, zi As Double, t As Double
n = Val(Command$): If n = 0 Then n = 1
w = 78: h = 400 * n
For y = 0 To h - 1
    line = ""
    For x = 0 To w - 1
        cr = x * 3# / w - 2.2
        ci = y * 2.4 / h - 1.2
        zr = 0: zi = 0
        For i = 1 To 200
            t = zr * zr - zi * zi + cr
            zi = 2 * zr * zi + ci
            zr = t
            If zr * zr + zi * zi > 4 Then Exit For
        Next
        If i > 200 Then line = line & "#": total = total + 1 Else line = line & Mid$(" .:-=+*%", i Mod 8 + 1, 1)
    Next
    If n = 1 And y Mod 80 = 0 Then Print line
Next
Print total
