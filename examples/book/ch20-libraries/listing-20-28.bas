Option Explicit
Dim web As Http, secret As String, body As String, reply As String
Set web = CreateObject("Http")
secret = "my-api-secret"
body = "{""order"": 1001}"
web.SetHeader "X-Signature", Base64Encode(HmacSha256(secret, body, True))
reply = web.Post("https://api.example.com/orders", body, "application/json")
