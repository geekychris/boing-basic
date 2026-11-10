Option Explicit
Dim lg As Logger, s As String

Set lg = CreateObject("Logger")
lg.FileName = "example.log"
lg.Pattern = "{level} [{source}] {message}"
lg.Source = "main"

lg.Info "program started"
lg.Debug "not written: the level is logInfo"
lg.Level = logDebug
lg.Debug "now debug messages are written"
lg.Source = "loader"
lg.Warning "no settings file, using the defaults"
lg.Log 45, "between Error and Fatal"
lg.Level = logError
lg.Info "not written: the level is logError"
lg.Error "can't open the picture"
Print lg.Count; "messages, the last: "; lg.LastMessage
lg.Close

Open "example.log" For Input As #1
Do Until EOF(1)
    Line Input #1, s
    Print s
Loop
Close #1
Kill "example.log"
