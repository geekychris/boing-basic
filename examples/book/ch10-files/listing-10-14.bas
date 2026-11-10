Dim f As Integer
f = FreeFile
Open "notes.txt" For Output As #f
Print #f, "Remember the milk"
Close #f
SetAttr "notes.txt", vbReadOnly
Print "read-only:"; (GetAttr("notes.txt") And vbReadOnly) <> 0
SetAttr "notes.txt", vbNormal
Print "read-only:"; (GetAttr("notes.txt") And vbReadOnly) <> 0
Print "changed in the last minute:"; Abs(DateDiff("s", FileDateTime("notes.txt"), Now)) < 60
Kill "notes.txt"

MkDir "work"
Print "directory:"; (GetAttr("work") And vbDirectory) <> 0
RmDir "work"

On Error Resume Next
f = GetAttr("no such file")
Print "missing file: error"; Err.Number
