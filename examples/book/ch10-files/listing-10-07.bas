Dim f As Integer, magic As Long, s As String, b As Byte

f = FreeFile
Open "data.bin" For Binary As #f
magic = &H424F4E47                  ' the letters B O N G
Put #f, , magic
Put #f, , "Boing!"
Print "length"; LOF(f); "position"; Seek(f)

Seek #f, 1
Get #f, , b
Print "first byte"; b; "("; Chr(b); ")"
s = Space(6)
Get #f, 5, s
Print "string ["; s; "]"; Loc(f); EOF(f)
Close #f

Kill "data.bin"
