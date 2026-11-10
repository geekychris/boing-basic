Dim web As Http, reply As String, token As String
Set web = CreateObject("Http")
token = Environ("API_TOKEN")
web.SetHeader "Accept", "application/json"
web.SetHeader "Authorization", "Bearer " & token
reply = web.Post("https://api.example.com/v1/items", "{""name"":""Boing""}", "application/json")
If web.Status <> 201 Then Print "Failed: "; web.Status; " "; reply
