Option Explicit
Dim web As Http, page As String, reply As String, name As String
Set web = CreateObject("Http")
page = web.Get("https://example.com/")
Print Utf8Decode(page)                           ' in: UTF-8 -> Latin-1, for the screen
name = "Zoë"
reply = web.Post("https://example.com/hello", Utf8Encode(name), "text/plain; charset=utf-8")
