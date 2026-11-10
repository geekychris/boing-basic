Option Explicit
Dim digest As String
digest = Sha256("abc", True)
Print Len(digest); " bytes"
Print HexEncode(digest)                      ' the same digits, in capitals
Print Base64Encode(HmacSha256("key", "The quick brown fox jumps over the lazy dog", True))
Print Sha256(Sha256("abc", True))            ' a hash of a hash: SHA-256 twice
