Option Explicit
Dim p As Process, rc As Long
Set p = CreateObject("Process")
rc = p.Run("echo hello world")
Print "exit code"; rc; ", output ["; Replace(p.Output, vbLf, "\n"); "]"
Print "the command was: "; p.CommandLine
