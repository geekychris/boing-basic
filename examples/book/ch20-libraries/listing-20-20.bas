Option Explicit
Dim q As String, url As String
q = "Boing BASIC & AmigaOS 4"
url = "https://example.com/search?q=" & UrlEncode(q) & "&page=2"
Print url
Print UrlEncode(Utf8Encode("Caf" & Chr(233)))
Print UrlDecode("Boing+BASIC%21"), UrlDecode("a%2Fb")
