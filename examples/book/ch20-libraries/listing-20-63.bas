Option Explicit
Dim p As Process, f As Variant
Set p = CreateObject("Process")
p.Run "List RAM: FILES LFORMAT %N"          ' the names of the files in RAM:, one per line
For Each f In p.OutputLines()
    Print "file: "; f
Next
