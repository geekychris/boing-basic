' Logger: levels, pattern, file output, rotation, console
Option Explicit
Dim lg As Logger, s As String, n As Long, i As Long

Set lg = CreateObject("Logger")
Print "defaults:"; lg.Level = logInfo; lg.Pattern; " ["; lg.FileName; "]"; lg.AutoFlush
On Error Resume Next
Kill "logtest.tmp"
Kill "logtest.tmp.old"
On Error GoTo 0
lg.FileName = "logtest.tmp"
lg.Pattern = "[{level}] {source}: {message}"
lg.Source = "Test"
lg.Debug "hidden"
lg.Info "one"
lg.Warning "two"
lg.Level = logDebug
lg.Debug "three"
lg.Error "four"
lg.Fatal "five"
lg.Log 35, "six (35 is a warning)"
lg.Level = logError
lg.Warning "hidden too"
lg.Level = logOff
lg.Fatal "off"
Print "count:"; lg.Count; " last: "; lg.LastMessage
lg.Close
Open "logtest.tmp" For Input As #1
Do Until EOF(1)
    Line Input #1, s
    Print s
Loop
Close #1
' the default pattern starts with the date and time
lg.Level = logInfo
lg.Pattern = "{date} {time}.{ms} {level} {message}"
lg.Info "stamped"
s = lg.LastMessage
Print Len(s); Mid(s, 5, 1); Mid(s, 8, 1); Mid(s, 14, 1); Mid(s, 20, 1); " "; Mid(s, 25)
' {line}: the BASIC line, also in the interpreter
lg.Pattern = "{line}"
lg.Info "x"
Print "line:"; lg.LastMessage
' rotation
lg.Pattern = "{message}"
lg.MaxSize = 200
For i = 1 To 20
    lg.Info "line number " & i & " of the rotation test"
Next
lg.Close
Print "rotated:"; FileLen("logtest.tmp.old") <= 200; FileLen("logtest.tmp") <= 200; FileLen("logtest.tmp") > 0
Kill "logtest.tmp"
Kill "logtest.tmp.old"
' console (standard error; the test runner shows it)
Set lg = CreateObject("Logger")
lg.Pattern = "{level}: {message}"
lg.Warning "to the console because there is no file"
lg.FileName = "logtest.tmp"
lg.Console = True
lg.Error "to both"
lg.Close
Print "file has:"; FileLen("logtest.tmp")
Kill "logtest.tmp"
On Error Resume Next
lg.Level = -1
Print "bad level:"; Err.Number
