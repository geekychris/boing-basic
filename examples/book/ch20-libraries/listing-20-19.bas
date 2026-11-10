Option Explicit
Dim web As Http, user As String, password As String, page As String
Set web = CreateObject("Http")
user = "ann": password = "secret"
web.SetHeader "Authorization", "Basic " & Base64Encode(user & ":" & password)
page = web.Get("https://example.com/private/")
