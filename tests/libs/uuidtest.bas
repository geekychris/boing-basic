' CreateUUID: version 4 format, lower case hex, all different
Option Explicit
Dim u As String, seen As New Collection, i As Long, dup As Long, bad As Long, k As Long, c As String
For i = 1 To 2000
    u = CreateUUID()
    If Not (u Like "????????-????-4???-????-????????????") Then bad = bad + 1
    If InStr("89ab", Mid(u, 20, 1)) = 0 Then bad = bad + 1
    For k = 1 To 36
        c = Mid(u, k, 1)
        If c <> "-" And InStr("0123456789abcdef", c) = 0 Then bad = bad + 1
    Next
    On Error Resume Next
    seen.Add i, u
    If Err.Number Then dup = dup + 1
    Err.Clear
    On Error GoTo 0
Next
Print "length:"; Len(CreateUUID()); " bad:"; bad; " duplicates:"; dup; " unique:"; seen.Count
Print TypeName(CreateUUID); CreateUUID <> CreateUUID
