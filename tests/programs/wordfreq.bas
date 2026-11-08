' Word frequencies: string processing, dynamic arrays, sorting by count
Option Explicit
Option Compare Text
Dim text As String
text = "The quick brown fox jumps over the lazy dog. The dog sleeps; the fox runs! " & _
       "A quick fox, a lazy dog, and THE end."
Dim words() As String, counts() As Long, n As Long

Function Clean(ByVal s As String) As String
    Dim i As Long, c As String, r As String
    For i = 1 To Len(s)
        c = Mid$(s, i, 1)
        If c Like "[a-z]" Or c = " " Then r = r & LCase$(c) Else r = r & " "
    Next
    Clean = r
End Function

Sub AddWord(ByVal w As String)
    Dim i As Long
    For i = 0 To n - 1
        If words(i) = w Then counts(i) = counts(i) + 1: Exit Sub
    Next
    ReDim Preserve words(n)
    ReDim Preserve counts(n)
    words(n) = w
    counts(n) = 1
    n = n + 1
End Sub

Dim parts() As String, i As Long, j As Long, t As Long, ts As String
parts = Split(Clean(text), " ")
For i = 0 To UBound(parts)
    If Len(parts(i)) > 0 Then AddWord parts(i)
Next
' sort by count desc, then word asc
For i = 0 To n - 2
    For j = i + 1 To n - 1
        If counts(j) > counts(i) Or (counts(j) = counts(i) And words(j) < words(i)) Then
            t = counts(i): counts(i) = counts(j): counts(j) = t
            ts = words(i): words(i) = words(j): words(j) = ts
        End If
    Next
Next
Print "distinct words:"; n
For i = 0 To 5
    Print Format(counts(i), "@@@"); "  "; words(i)
Next
Print "longest: ";
ts = ""
For i = 0 To n - 1
    If Len(words(i)) > Len(ts) Then ts = words(i)
Next
Print ts; " ("; Len(ts); ")"
Print UCase$(Left$(text, 9)); "|"; StrReverse(Mid$(text, 5, 5)); "|"; InStr(text, "DOG"); InStrRev(text, "the")
Print Replace(Left$(text, 19), " ", "_")
