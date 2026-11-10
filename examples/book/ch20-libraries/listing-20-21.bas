Option Explicit
Dim body As String, fields As Dictionary, pair As Variant, kv As Variant, k As Variant
body = "name=Boing+BASIC&year=1985&note=100%25+BASIC"
Set fields = CreateObject("Dictionary")
For Each pair In Split(body, "&")
    kv = Split(pair, "=")
    fields(UrlDecode(kv(0))) = Utf8Decode(UrlDecode(kv(1)))
Next
For Each k In fields
    Print k; " = "; fields(k)
Next
