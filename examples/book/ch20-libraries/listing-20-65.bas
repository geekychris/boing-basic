Option Explicit
Dim p As Process, v As Variant, found As Boolean
Set p = CreateObject("Process")
p.SetEnv "BOING_GREETING", "hello from Boing"
Print "GetEnv: "; p.GetEnv("BOING_GREETING")
Print "Environ: "; Environ("BOING_GREETING")
For Each v In p.Environment()
    If v = "BOING_GREETING=hello from Boing" Then found = True
Next
Print "in Environment():"; found
p.Run "echo $BOING_GREETING"                ' the command sees it too
Print "the command printed: "; p.OutputLines()(0)
p.SetEnv "BOING_GREETING"                   ' removed
Print "removed: ["; p.GetEnv("BOING_GREETING"); "]"
