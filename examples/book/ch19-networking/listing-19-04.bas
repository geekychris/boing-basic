Dim web As Http, reply As String
Set web = CreateObject("Http")
reply = web.Post("https://httpbin.org/post", "name=Boing&colour=red")
Print web.Status
