Option Explicit
Dim s As String, packed As String, i As Long

For i = 1 To 200
    s = s & "Line " & i & " of a text that repeats itself a lot." & vbLf
Next
packed = Compress(s)
Print "original:"; Len(s); "bytes"
Print "gzip, a tenth or less: "; Len(packed) <= Len(s) \ 10
Print "zlib, level 9, recognised: "; Decompress(Compress(s, zipZlib, 9)) = s
Print "stored (level 0):"; Len(Compress(s, zipGzip, 0)); "bytes"
Print "round trip ok: "; Decompress(packed) = s
Print "raw deflate ok: "; Decompress(Compress(s, zipDeflate), zipDeflate) = s
