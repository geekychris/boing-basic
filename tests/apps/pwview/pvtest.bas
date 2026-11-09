' Penwright commands and page drawing
Option Explicit

Private Function FileText(ByVal p As String) As String
    Dim fn As Integer, s As String
    fn = FreeFile
    Open p For Binary As #fn
    s = Space$(LOF(fn))
    Get #fn, , s
    Close #fn
    FileText = s
End Function

Private Sub Run(ByVal script As String)
    Dim lines() As String, i As Long, res As String
    lines = Split(Replace(script, vbCr, ""), vbLf)
    For i = 0 To UBound(lines)
        If Trim$(lines(i)) <> "" And Left$(Trim$(lines(i)), 1) <> ";" Then
            res = RunCommand(lines(i))
            If res <> "" Or PwRC <> 0 Then Print lines(i); " -> "; res; IIf(PwRC <> 0, " [rc " & PwRC & "]", "")
        End If
    Next i
End Sub

Sub Main()
    Dim cv As Object, p As Long
    NewDoc
    LoadDictionary "../../../examples/penwright/penwright.dict", ""
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 640, 440
    ViewInit cv, 640, 440
    Run FileText("../../../examples/penwright/tests/letter.pws")
    For p = 0 To NP - 1
        Print p; StyleName(pStyle(p)); pAlign(p); " ["; pText(p); "] "; RunsOf(p)
    Next p
    DrawDoc cv
    Print "page hash "; Hex$(cv.Hash); " height "; DocHeight()
    If Command$ = "shot" Then cv.SaveImage "page.ppm"
    ' cursor movement
    SetCursor 3, 0, False
    MoveCaret "D", False
    Print "down: "; curP; curO
    MoveCaret "END", False
    Print "end: "; curP; curO
    MoveCaret "HOME", False
    Print "home: "; curP; curO
    MoveCaret "WR", False
    MoveCaret "WR", True
    Print "word right x2 (extend): "; curP; curO; " sel ["; RunCommand("GETSELECTION"); "]"
    MoveCaret "BOT", False
    MoveCaret "U", False
    Print "bottom then up: "; curP; curO
    MoveCaret "TOP", False
    Print "top: "; curP; curO
    Run "FIND rewriting" & vbLf & "GETSELECTION" & vbLf & "FIND nothing-like-this" & vbLf & "SETCURSOR 0 0" & vbLf & "SPELLNEXT" & vbLf & "SUGGEST thsi" & vbLf & "SPELLNEXT"
    Run "SELECT 4 0 4 4" & vbLf & "COPY" & vbLf & "SETCURSOR 7 0" & vbLf & "PASTE" & vbLf & "GETPARA 7" & vbLf & "UNDO" & vbLf & "GETPARA 7"
    Run "REPLACEALL ""and"" ""&"" WORD" & vbLf & "GETPARA 3" & vbLf & "UNDO" & vbLf & "PARACOUNT" & vbLf & "STYLE nonsense" & vbLf & "FOO" & vbLf & "VERSION"
    Run "SAVE pw.pwd" & vbLf & "NEW" & vbLf & "PARACOUNT" & vbLf & "OPEN pw.pwd" & vbLf & "PARACOUNT" & vbLf & "GETPARA 0" & vbLf & "EXPORT HTML pw.html" & vbLf & "EXPORT RTF pw.rtf" & vbLf & "OPEN pw.rtf" & vbLf & "GETPARA 3"
    Print "html bytes "; Len(FileText("pw.html"))
    Kill "pw.pwd": Kill "pw.html": Kill "pw.rtf"
End Sub
