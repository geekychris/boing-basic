' Input # reads back what Write # wrote: #TRUE#, #FALSE#, #date#, #NULL#, quoted strings
Sub Main()
    Dim f As Integer, b As Boolean, c As Boolean, d As Date, s As String, n As Long, v As Variant
    f = FreeFile
    Open "wi_test.txt" For Output As #f
    Write #f, True, False, #3/4/2025 10:20:30 AM#, "text, with comma", 42, Null
    Close #f
    Open "wi_test.txt" For Input As #f
    Input #f, b, c, d, s, n, v
    Close #f
    Print b; c; Year(d); Month(d); Day(d); Hour(d); s; n; IsNull(v)
    Kill "wi_test.txt"
End Sub
