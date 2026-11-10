Sub Twice(v As Variant)
    v = v * 2
End Sub

Sub Shout(v)
    v = UCase$(v) & "!"
End Sub

Sub MakeText(v)
    v = "ten"
End Sub

Dim n As Long, s As String
n = 21: s = "hello"
Twice n
Shout s
Print n; s
Twice (n)                 ' in parentheses: a copy
Print n
On Error Resume Next
MakeText n                ' "ten" can't go back into a Long
Print "error"; Err.Number; n
