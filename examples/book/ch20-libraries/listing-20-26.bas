Option Explicit
Dim f As Integer, data As String

f = FreeFile
Open "test.dat" For Output As #f
Print #f, "Boing BASIC";
Close #f

f = FreeFile
Open "test.dat" For Binary Access Read As #f
data = Space(LOF(f))
Get #f, , data
Close #f
Kill "test.dat"

Print Len(data); " bytes, CRC-32 "; Hex(Crc32(data))
Print "SHA-256 "; Sha256(data)
