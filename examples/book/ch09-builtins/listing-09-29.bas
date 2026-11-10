Dim i As Integer
For i = 0 To 15
    Print Right$("00000" & Hex(QBColor(i)), 6); " ";
    If i = 7 Then Print
Next
Print
Print QBColor(12) = RGB(255, 0, 0); QBColor(9) = vbBlue
