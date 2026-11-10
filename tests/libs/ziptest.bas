' Compress/Decompress/CRC32 and Zip archives: create, list, read, extract, foreign archives, errors
Option Explicit
Dim z As Zip, s As String, c As String, i As Long, n As Long, t As String

' functions
s = ""
For i = 1 To 500: s = s & "Boing BASIC " & i & vbLf: Next
c = Compress(s)
Print "gzip:"; Len(s); Len(c) < Len(s) \ 3; Asc(c) = 31; Asc(Mid(c, 2, 1)) = 139; Decompress(c) = s; Decompress(c, zipGzip) = s
c = Compress(s, zipZlib, 9)
Print "zlib:"; Asc(c) = 120; Decompress(c) = s; Decompress(c, zipZlib) = s
c = Compress(s, zipDeflate, 1)
Print "deflate:"; Decompress(c, zipDeflate) = s
Print "level 0 bigger:"; Len(Compress(s, zipGzip, 0)) > Len(s)
Print "empty:"; Len(Decompress(Compress(""))); " binary:"; Decompress(Compress(Chr(0) & Chr(255) & Chr(0))) = Chr(0) & Chr(255) & Chr(0)
Print "crc:"; Hex(CRC32("123456789")); " "; CRC32(""); " "; Hex(CRC32("The quick brown fox jumps over the lazy dog"))

' a foreign archive (made with Info-ZIP's zip)
Set z = CreateObject("Zip")
z.Open "fixture.zip"
Print "entries:"; z.Count
For i = 0 To z.Count - 1
    Print " "; z.Name(i); z.Size(i); z.IsFolder(i); z.CompressedSize(i) <= z.Size(i) Or z.Size(i) < 20; " "; Year(z.FileDate(i))
Next
Print "read:"; z.Read("hello.txt") = "hello from zip" & vbLf; Len(z.Read(3)); z.IndexOf("DOCS/DATA.BIN"); z.IndexOf("nope")
Print "extracted:"; z.ExtractAll("zipout")
Print FileLen("zipout/docs/sub/big.txt"); FileLen("zipout/docs/data.bin"); Dir("zipout/docs/sub", vbDirectory) <> ""
z.Extract "hello.txt", "zipout/copy.txt"
Print FileLen("zipout/copy.txt")
z.Close

' make one: text, files, a folder; stored and deflated
Set z = CreateObject("Zip")
z.Create "made.zip"
z.AddText "readme.txt", "Made by Boing BASIC" & vbCrLf
z.AddText "empty.txt", ""
z.AddFile "zipout/docs/data.bin"
z.AddFile "zipout/hello.txt", "texts/hello.txt"
z.AddFolder "zipout/docs", "tree"
z.Level = 0
z.AddText "stored.txt", String(1000, "s")
Print "written:"; z.Count
z.Close
z.Open "made.zip"
For i = 0 To z.Count - 1
    t = t & z.Name(i) & "(" & z.Size(i) & ") "
Next
Print t
Print z.Read("stored.txt") = String(1000, "s"); z.CompressedSize("stored.txt"); z.Read("tree/sub/big.txt") = String(2000, "x") Or Len(z.Read("tree/sub/big.txt")) = 26000
Print z.Read("data.bin") = z.Read("tree/data.bin"); Len(z.Read("empty.txt")); z.Read("readme.txt") = "Made by Boing BASIC" & vbCrLf
z.Close

' errors
On Error Resume Next
z.Open "no-such.zip"
Print "missing:"; Err.Number: Err.Clear
Open "notzip.tmp" For Output As #1: Print #1, "this is not a zip file at all"; : Close #1
z.Open "notzip.tmp"
Print "not zip:"; Err.Number; " "; Err.Description: Err.Clear
z.Open "made.zip"
s = z.Read("missing.txt")
Print "no entry:"; Err.Number: Err.Clear
s = z.Read(99)
Print "index:"; Err.Number: Err.Clear
z.AddText "x", "y"
Print "read-only:"; Err.Number: Err.Clear
z.Close
z.Create "bad.zip"
z.AddText "../evil.txt", "x"
Print "unsafe:"; Err.Number: Err.Clear
z.Close
s = Decompress("garbage that is not compressed")
Print "corrupt:"; Err.Number: Err.Clear
s = Compress("x", 7)
Print "format:"; Err.Number: Err.Clear
' a damaged archive: flip a byte of compressed data
Dim b As String
Open "made.zip" For Binary As #1
b = Space(LOF(1)): Get #1, 1, b
Close #1
Mid(b, 60, 1) = Chr(Asc(Mid(b, 60, 1)) Xor 255)
Open "broken.zip" For Binary As #1: Put #1, 1, b: Close #1
z.Open "broken.zip"
s = z.Read(0)
Print "damaged:"; Err.Number: Err.Clear
z.Close
Kill "notzip.tmp": Kill "made.zip": Kill "bad.zip": Kill "broken.zip"
