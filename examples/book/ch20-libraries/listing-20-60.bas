Option Explicit
Dim p As Process
Set p = CreateObject("Process")
If p.Run("Version") = 0 Then Print "This is "; p.Output
