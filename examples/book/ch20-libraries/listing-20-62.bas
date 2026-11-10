Option Explicit
Dim p As Process
Set p = CreateObject("Process")
If p.Run("Search S: Boing QUIET") = 5 Then
    Print "No file in S: mentions Boing"
End If
If p.Run("Type nonexistent-file") <> 0 Then
    Print "Type failed with"; p.ExitCode; ": "; p.Output; p.ErrorOutput
End If
