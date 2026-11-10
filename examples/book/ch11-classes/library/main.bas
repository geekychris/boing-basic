' main.bas
Option Explicit

Sub Main()
    Dim s As New Shelf, b As Book
    s.Name = "Science fiction"
    s.Add "Dune", 1965
    s.Add "Solaris", 1961
    s.Add("Neuromancer", 1984).Year = 1984
    Print s.Count; "books"
    Print s("Dune").Describe()          ' the default member Item
    Print s.Item(2).Title               ' by position, from 1
    For Each b In s.Books
        Print " - "; b.Describe()
    Next
    s.Remove "Solaris"
    Print s.Count; "books"
    With s("Neuromancer")
        .Title = .Title & " (Ace)"
        Print .Describe()
    End With
    On Error Resume Next
    Set b = s("Ubik")
    Print "Error"; Err.Number; Err.Description
    On Error GoTo 0
    Set b = Nothing
    s.Clear                             ' without this the shelf is never released
End Sub
