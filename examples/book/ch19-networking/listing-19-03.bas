Dim web As Http, n As Long
Set web = CreateObject("Http")
n = web.GetToFile("https://example.com/", "RAM:example.html")
Print n; " bytes saved"
