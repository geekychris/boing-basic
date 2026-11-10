Dim g As New Counter
Sub Main()
    Dim c As New Counter, h As New Holder
    c.Add 5
    g.Add 2: g.Add 3
    Print "auto"; c.Value; g.Value; g.Count
    Set c = Nothing
    c.Add 1
    Print "renew"; c.Value; TypeName(c)
    h.k.Add 9
    Print "field"; h.k.Value
End Sub
