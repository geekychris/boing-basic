Option Explicit
Dim web As Http, user As Variant
Set web = CreateObject("Http")
web.SetHeader "Accept", "application/json"
On Error GoTo Failed
user = JsonParse(web.Get("https://jsonplaceholder.typicode.com/users/1"))
If web.Status <> 200 Then Print "The server said "; web.Status: End
Print Utf8Decode(user("name")); " lives in "; Utf8Decode(user("address")("city"))
End
Failed:
Print "Error"; Err.Number; ": "; Err.Description
