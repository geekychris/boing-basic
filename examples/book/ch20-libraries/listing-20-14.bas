Option Explicit
Dim web As Http, post As Dictionary, reply As Variant
Set web = CreateObject("Http")
Set post = CreateObject("Dictionary")
post("title") = Utf8Encode("Hello from the Amiga")
post("userId") = 1
reply = JsonParse(web.Post("https://jsonplaceholder.typicode.com/posts", _
                           JsonStringify(post), "application/json"))
If web.Status = 201 Then Print "Created post"; reply("id")
