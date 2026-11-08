Public keep As Acc
Dim a As New Acc, i As Long
a.Name = "a"
For i = 1 To 1000
    a.Add i
    a.Total = a.Total + 1
Next
Print a.Total; a.Avg; a.Sng
On Error Resume Next
a.IncK: a.IncK: a.IncK: a.IncK
Print "k"; a.GetK; Err.Number
Err.Clear
On Error GoTo 0
Set keep = New Acc
keep.Name = "keep"
keep.DropGlobal
Print "after"; keep Is Nothing
Set a = Nothing
Print "end"
