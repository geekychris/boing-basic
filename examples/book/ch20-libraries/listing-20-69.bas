Option Explicit
Dim lg As Logger, i As Long

Set lg = CreateObject("Logger")
lg.FileName = "server.log"
lg.Pattern = "{level} {message}"
lg.MaxSize = 300
For i = 1 To 30
    lg.Info "request number " & i & " answered"
Next
lg.Close
Print "server.log:"; FileLen("server.log"); "bytes"
Print "server.log.old:"; FileLen("server.log.old"); "bytes"
Kill "server.log"
Kill "server.log.old"
