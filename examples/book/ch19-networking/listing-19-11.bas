Option Explicit
Dim web As Http, ended As Boolean
Set web = CreateObject("Http")
web.OnDone = "Finished"

web.GetAsync "ftp://example.com/readme.txt"       ' Http speaks http:// and https:// only
ended = web.Wait()
Print "ended: " & ended & ", error " & web.ErrorNumber & ": " & web.ErrorText

web.GetAsync "http://127.0.0.1:1/"                 ' nothing listens on port 1
ended = web.Wait(10000)
Print "error " & web.ErrorNumber & ": " & web.ErrorText

Sub Finished()
    Print "Finished: Busy is " & web.Busy & ", Status " & web.Status
End Sub
