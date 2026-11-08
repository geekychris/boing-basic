' Select Case over integers and strings
Dim i As Long, n As Long, s As Long, w As String
n = Val(Command$): If n = 0 Then n = 1
For i = 1 To 5000000 * n
    Select Case i Mod 10
        Case 0: s = s + 1
        Case 1, 2: s = s + 2
        Case 3 To 6: s = s + 3
        Case Is > 8: s = s - 1
        Case Else: s = s + 5
    End Select
Next
For i = 1 To 500000 * n
    Select Case Chr$(97 + i Mod 5)
        Case "a": w = "A"
        Case "b", "c": w = "BC"
        Case Else: w = ""
    End Select
    s = s + Len(w)
Next
Print s
