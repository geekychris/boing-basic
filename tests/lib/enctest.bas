' enctest.bas - Utf8Encode/Decode, Base64, Url, Hex
Option Explicit
Dim s As String, u As String, i As Long, all As String, b As String

Function Bytes(x As String) As String
    Dim i As Long, r As String
    For i = 1 To Len(x): r = r & Right("0" & Hex(Asc(Mid(x, i, 1))), 2) & " ": Next
    Bytes = RTrim(r)
End Function

' UTF-8 <-> Latin-1
s = "Caf" & Chr(233) & " " & Chr(169) & " A" & Chr(255)
u = Utf8Encode(s)
Print Len(s), Len(u), Bytes(u)
Print Utf8Decode(u) = s
Print Utf8Decode(Chr(&HE2) & Chr(&H82) & Chr(&HAC) & "5")                     ' the euro sign isn't Latin-1
Print Utf8Decode(Chr(&HE2) & Chr(&H82) & Chr(&HAC) & "5", "EUR")
Print Utf8Decode("a" & Chr(&HFF) & "b" & Chr(&HC3)), Utf8Decode(Chr(&HC0) & Chr(&H80))   ' invalid bytes, overlong
Print Bytes(Utf8Decode(Chr(&HF0) & Chr(&H9F) & Chr(&H98) & Chr(&H80), ""))
Print Utf8Decode("plain ascii"), Len(Utf8Encode(""))
For i = 0 To 255: all = all & Chr(i): Next
Print Utf8Decode(Utf8Encode(all)) = all

' Base64 (RFC 4648 test vectors)
Print Base64Encode(""); "|"; Base64Encode("f"); "|"; Base64Encode("fo"); "|"; Base64Encode("foo"); "|"; Base64Encode("foobar")
Print Base64Decode("Zm9vYmFy"), Base64Decode("Zm9vYg=="), Base64Decode("Zm9v YmE=" & vbCrLf)
Print Base64Decode(Base64Encode(all)) = all
b = Base64Encode(String(100, "x"), 76)
Print Len(b), InStr(b, vbCrLf), Base64Decode(b) = String(100, "x")
Print Base64Decode("-_8"), Bytes(Base64Decode("-_8"))                  ' the URL-safe alphabet
Print Base64Encode("user:pass")

' URL encoding
Print UrlEncode("a b&c=d/e?f~g.h_i-j"), UrlEncode(Chr(233))
Print UrlDecode("a%20b%26c%3Dd+e"), UrlDecode(UrlEncode(all)) = all
Print UrlEncode(Utf8Encode("Caf" & Chr(233)))

' hex
Print HexEncode("Boing!"), HexDecode("426F696E6721"), HexDecode("42 6f:69 6E")
Print HexDecode(HexEncode(all)) = all

' errors: 31301
On Error Resume Next
s = Base64Decode("Zm9v!")
Print Err.Number; Err.Description
Err.Clear
s = Base64Decode("Zg=x")
Print Err.Number; Err.Description
Err.Clear
s = Base64Decode("Z")
Print Err.Number; Err.Description
Err.Clear
s = UrlDecode("100%")
Print Err.Number; Err.Description
Err.Clear
s = HexDecode("ABC")
Print Err.Number; Err.Description
Err.Clear
s = HexDecode("zz")
Print Err.Number; Err.Description
