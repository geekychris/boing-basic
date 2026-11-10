' Main.bas - makes two Counter objects and uses them.
Option Explicit

Sub Main()
    Dim apples As Counter, pears As Counter
    Set apples = New Counter
    Set pears = New Counter
    apples.Name = "apples"
    pears.Name = "pears"
    apples.Add
    apples.Add 4
    pears.Add 2
    Print apples.Name; apples.Count
    Print pears.Name; pears.Count
End Sub
