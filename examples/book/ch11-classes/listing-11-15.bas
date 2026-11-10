Option Explicit
Type Rect
    Left As Long
    Top As Long
    Width As Long
    Height As Long
End Type

Dim r As Rect
With r
    .Left = 10
    .Top = 20
    .Width = 100
    .Height = .Width \ 2            ' members can be read too
    Print .Left; .Top; .Width; .Height
End With

Dim jobs As New Collection
With jobs
    .Add "backup"
    .Add "print"
    Print .Count; "jobs, first: "; .Item(1)
End With
