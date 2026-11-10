Option Explicit
Dim web As Http, page As String
Set web = CreateObject("Http")
page = web.Get("https://example.com/")
If web.Status = 200 Then
    Print Len(page); " bytes of "; web.ContentType
Else
    Print "The server said "; web.Status; " "; web.StatusText
End If
