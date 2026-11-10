Option Explicit
Dim p As Process
Set p = CreateObject("Process")
p.Run "Echo ?", "hello" & vbLf
Print p.Output
