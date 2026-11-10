Option Explicit
Dim web As Http
Set web = CreateObject("Http")
web.GetAsync "https://example.com/slow-report"
Do Until web.Wait(1000)
    Print "still waiting ..."
Loop
Print web.Status
