' hashtest.bas - Crc32, Md5, Sha1, Sha256, HmacSha1, HmacSha256 (published test vectors)
Option Explicit
Dim s As String, i As Long, big As String

Print Hex(Crc32("")), Hex(Crc32("123456789")), Hex(Crc32("The quick brown fox jumps over the lazy dog"))
Print Md5("")
Print Md5("a")
Print Md5("abc")
Print Md5("message digest")
Print Md5("12345678901234567890123456789012345678901234567890123456789012345678901234567890")
Print Sha1("")
Print Sha1("abc")
Print Sha1("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
Print Sha256("")
Print Sha256("abc")
Print Sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
' a million "a"s (FIPS 180 long message vector)
big = String(1000000, "a")
Print Sha1(big)
Print Sha256(big)
' block boundaries: 55, 56, 63, 64, 65 bytes
For i = 55 To 65
    If i = 55 Or i = 56 Or i = 63 Or i = 64 Or i = 65 Then Print i; Md5(String(i, "x")); " "; Left(Sha256(String(i, "x")), 16)
Next
' HMAC (RFC 2202 / RFC 4231)
Print HmacSha1(String(20, Chr(&HB)), "Hi There")
Print HmacSha1("Jefe", "what do ya want for nothing?")
Print HmacSha256(String(20, Chr(&HB)), "Hi There")
Print HmacSha256("Jefe", "what do ya want for nothing?")
Print HmacSha256(String(131, Chr(&HAA)), "Test Using Larger Than Block-Size Key - Hash Key First")
' raw digests
s = Sha256("abc", True)
Print Len(s), HexEncode(s) = UCase(Sha256("abc")), Len(Md5("abc", True)), Len(Sha1("abc", True)), Len(HmacSha256("k", "m", True))
Print Base64Encode(HmacSha256("key", "message", True))
' binary input
s = ""
For i = 0 To 255: s = s & Chr(i): Next
Print Hex(Crc32(s)), Md5(s)
