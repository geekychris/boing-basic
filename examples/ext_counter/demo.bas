' demo.bas - uses the counter extension (Extension=counter in demo.bbp)
Sub Main()
    Dim c As Counter, i As Long
    Set c = CreateObject("Counter")
    For i = 1 To 10
        c.Add i
    Next
    Print "value"; c.Value; "count"; c.Count
    c.Value = 100
    Print "set"; c.Value; TypeName(c)
    c.Reset
    Print "reset"; c.Value; c.Count
    Print "clamp"; Clamp(15, 0, 10); Clamp(-3, 0, 10); Clamp(7, 0, 10)
End Sub
