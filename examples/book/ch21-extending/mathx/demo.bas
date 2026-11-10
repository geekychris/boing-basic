' demo.bas - uses the mathx extension (Extension=mathx in demo.bbp)
Dim WithEvents rain As Stats

Sub rain_NewMax(ByVal x As Double)
    Print "  new maximum:"; x
End Sub

Sub Main()
    Dim s As Stats, v As Variant
    Print Clamp(15, 0, 10); Clamp(-2.5, 0, 10); Lerp(0, 100, 0.25)
    Set rain = New Stats
    Set s = rain
    s.Name = "Rainfall"
    For Each v In Array(12, 7.5, 3, 20.25, 9)
        s.Add v
    Next
    Print s.Name; ":"; s.Count; "values, mean"; s.Mean; "from"; s.Min; "to"; s.Max
    s.Clear
    On Error Resume Next
    Print s.Mean
    Print "Error"; Err.Number; Err.Description
End Sub
