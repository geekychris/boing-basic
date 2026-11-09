' Open on a missing file: For Input and For Binary/Random Access Read raise 53 and create
' nothing; Binary without Access Read creates it (as VB6)
Sub Main()
    Dim f As Integer, b As Byte, p As String
    p = "oa_missing.bin"
    If Dir$(p) <> "" Then Kill p
    On Error Resume Next
    f = FreeFile
    Open p For Binary Access Read As #f
    Print "binary read:"; Err.Number; Dir$(p) <> ""
    Err.Clear
    Open p For Random Access Read As #f Len = 4
    Print "random read:"; Err.Number; Dir$(p) <> ""
    Err.Clear
    Open p For Input As #f
    Print "input:"; Err.Number; Dir$(p) <> ""
    Err.Clear
    On Error GoTo 0
    Open p For Binary Access Write As #f
    b = 7
    Put #f, , b
    Close #f
    Print "binary write creates:"; Dir$(p) <> ""; FileLen(p)
    Open p For Binary Access Read As #f
    Get #f, 1, b
    Close #f
    Print "binary read existing:"; b
    Kill p
    Open p For Binary As #f
    Close #f
    Print "binary creates:"; Dir$(p) <> ""
    Kill p
End Sub
