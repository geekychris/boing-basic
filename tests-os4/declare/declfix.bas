' Declare fixes on AmigaOS 4: As String returns the C string; a misspelt library is 48; TagList
' copies temporary strings; Single arguments are rounded (VM and native alike)
Declare Function FilePart Lib "dos.library" (ByVal path As String) As String
Declare Function FilePartX Lib "dosx.library" Alias "FilePart" (ByVal path As String) As String
Declare Function ToUpper Lib "utility.library" (ByVal c As Single) As Long
Sub Main()
    Dim t As Long, n As Long, s As String
    Print "filepart "; FilePart("Work:Games/Tank/tank.bbp")
    On Error Resume Next
    s = FilePartX("a/b")
    Print "misspelt"; Err.Number
    Err.Clear
    On Error GoTo 0
    n = 7
    t = TagList(1, "Title " & CStr(n), 2, 99)
    s = String$(40, "x")       ' reuse memory a freed temporary would have used
    Print "taglist "; PeekS(PeekL(t + 4)); PeekL(t + 12)
    FreeTagList t
    Print "toupper"; ToUpper(97.6); ToUpper(98.4)   ' rounded: 66 66 (truncated would be 65 66)
End Sub
