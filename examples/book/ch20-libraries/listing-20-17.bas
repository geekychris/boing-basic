Option Explicit
Dim amiga As String, utf8 As String, euro As String
amiga = "Caf" & Chr(233)                       ' "Café" in Latin-1: 4 bytes
utf8 = Utf8Encode(amiga)
Print Len(amiga); Len(utf8); " "; HexEncode(utf8)
Print Utf8Decode(utf8) = amiga                 ' and back
euro = HexDecode("E282AC") & "5"               ' "5 euros" in UTF-8: the euro sign is 3 bytes
Print Utf8Decode(euro); " "; Utf8Decode(euro, "EUR "); " "; Utf8Decode(euro, "")
Print Utf8Decode(HexDecode("41FF42"))          ' FF is never valid UTF-8
