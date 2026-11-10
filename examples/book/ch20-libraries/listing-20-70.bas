Option Explicit
Dim lg As Logger
Set lg = CreateObject("Logger")
lg.Pattern = "{level}: {message}"
If InStr(LCase(Command), "debug") > 0 Then lg.Level = logDebug
lg.Debug "only with DEBUG on the command line"
lg.Info "to the console, because there is no FileName"
