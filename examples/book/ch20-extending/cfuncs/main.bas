' main.bas - calls the C functions in cfuncs.c (CSource=cfuncs.c in cfuncs.bbp)
Declare Function CRC32 Lib "C" Alias "crc32_text" (ByVal text As String) As Long
Declare Function Distance3 Lib "C" Alias "distance3" (ByVal x As Double, ByVal y As Double, ByVal z As Double) As Double
Declare Function Ordinal Lib "C" Alias "ordinal" (ByVal n As Long) As String

Sub Main()
    Dim i As Long
    Print Hex(CRC32("The quick brown fox jumps over the lazy dog"))
    Print Distance3(2, 3, 6)
    For i = 1 To 4
        Print Ordinal(i); " ";
    Next
    Print Ordinal(11); " "; Ordinal(22); " "; Ordinal(113)
End Sub
