Option Explicit
Dim counts As Dictionary, w As Variant
Set counts = CreateObject("Dictionary")
For Each w In Split("red green red blue red green", " ")
    counts(w) = counts(w) + 1
Next
For Each w In counts
    Print w; " x"; counts(w)
Next
