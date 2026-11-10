' Switch, Filter, QBColor, Date$/Time$, GetAttr/SetAttr, FileDateTime, GetAllSettings,
' Lock/Unlock, Reset, Width #
Sub Main()
    Dim a, r, i As Integer, f As Integer, s As String, x As Long, t As Date, st
    ' Switch
    For x = 1 To 4
        r = Switch(x = 1, "one", x = 2, "two", x > 2 And x < 4, "three")
        If IsNull(r) Then Print "null" Else Print r
    Next
    ' Filter
    a = Split("apple,Banana,cherry,grape,PEAR", ",")
    r = Filter(a, "an")
    Print UBound(r); Join(r, "+")
    r = Filter(a, "a", False)
    Print UBound(r); Join(r, "+")
    r = Filter(a, "AP", True, vbTextCompare)
    Print UBound(r); Join(r, "+")
    r = Filter(a, "zzz")
    Print UBound(r)
    ' QBColor
    Print Hex(QBColor(0)); " "; Hex(QBColor(1)); " "; Hex(QBColor(4)); " "; Hex(QBColor(14)); " "; Hex(QBColor(15))
    ' Date$ / Time$: shapes
    s = Date$
    Print Len(s); Mid$(s, 3, 1); Mid$(s, 6, 1); Val(Left$(s, 2)) = Month(Date)
    s = Time$
    Print Len(s); Mid$(s, 3, 1); Mid$(s, 6, 1)
    ' files
    f = FreeFile
    Open "vbmisc.txt" For Output As #f
    Width #f, 5
    Print #f, "abcdefghij"
    Print #f, "xy"
    Lock #f
    Lock #f, 1 To 3
    Unlock #f, 2
    Unlock f
    Close #f
    f = FreeFile
    Open "vbmisc.txt" For Input As #f
    Do While Not EOF(f): Line Input #f, s: Print "["; s; "]";: Loop
    Print
    Close #f
    Print "attr"; GetAttr("vbmisc.txt") And 17
    SetAttr "vbmisc.txt", vbReadOnly
    Print "ro"; GetAttr("vbmisc.txt") And 1
    SetAttr "vbmisc.txt", vbNormal
    Print "rw"; GetAttr("vbmisc.txt") And 1
    MkDir "vbmisc_d"
    Print "dir"; GetAttr("vbmisc_d") And 16
    RmDir "vbmisc_d"
    t = FileDateTime("vbmisc.txt")
    Print "mtime"; Abs(DateDiff("s", t, Now)) < 120
    Kill "vbmisc.txt"
    On Error Resume Next
    x = GetAttr("no_such_file")
    Print "missing"; Err.Number
    Err.Clear
    Lock #9
    Print "lock closed"; Err.Number
    Err.Clear
    On Error GoTo 0
    ' Reset closes every file
    Open "vbmisc1.txt" For Output As #1
    Open "vbmisc2.txt" For Output As #2
    Reset
    Print "free"; FreeFile
    Kill "vbmisc1.txt": Kill "vbmisc2.txt"
    ' GetAllSettings
    SaveSetting "BBTestVbMisc", "Main", "Width", "640"
    SaveSetting "BBTestVbMisc", "Main", "Height", "480"
    st = GetAllSettings("BBTestVbMisc", "Main")
    For i = LBound(st, 1) To UBound(st, 1)
        Print st(i, 0); "="; st(i, 1)
    Next
    DeleteSetting "BBTestVbMisc", "Main"
    Print "after delete"; IsEmpty(GetAllSettings("BBTestVbMisc", "Main"))
End Sub
