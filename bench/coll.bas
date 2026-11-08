' Collection: Add with keys, lookup, For Each, Remove
Dim c As Collection, i As Long, r As Long, n As Long, s As Long, v As Variant
n = Val(Command$): If n = 0 Then n = 1
For r = 1 To 200 * n
    Set c = New Collection
    For i = 1 To 500
        c.Add i * 2, "k" & i
    Next
    For i = 1 To 500 Step 7
        s = s + c("k" & i)
    Next
    For Each v In c
        s = (s + v) And &HFFFFF
    Next
    For i = 1 To 100: c.Remove 1: Next
    s = s + c.Count
Next
Print s
