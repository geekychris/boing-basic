Option Explicit
Dim b As String
b = Base64Encode("Boing!")
Print b, Base64Decode(b)
Print Base64Encode("Boi"), Base64Encode("Bo"), Base64Encode("B")
Print Base64Decode("Qm9p bmch"), Base64Decode("Qm8")       ' spaces skipped, "=" optional
Print HexEncode(Base64Decode("-_8")), HexEncode(Base64Decode("+/8="))   ' both alphabets
Print Len(Base64Encode(String(100, "x"), 76))              ' 76 + CR LF + 60
