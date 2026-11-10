Option Explicit
Dim web As Http, page As String
Set web = CreateObject("Http")
On Error GoTo Failed
page = web.Get("https://no-such-host.example/")
Print "Fetched "; Len(page); " bytes"
End
Failed:
Print "Can't fetch the page: "; Err.Description
