Option Explicit

Declare Function Dos_Open Lib "dos.library" Alias "#4" (ByVal name_ As String, ByVal accessMode As Long) As Long
Declare Function Dos_Close Lib "dos.library" Alias "#5" (ByVal file As Long) As Long
Declare Function Dos_Read Lib "dos.library" Alias "#6" (ByVal file As Long, ByVal buffer As Long, ByVal length As Long) As Long
Declare Function Dos_Write Lib "dos.library" Alias "#7" (ByVal file As Long, ByVal buffer As Long, ByVal length As Long) As Long

Const MODE_OLDFILE = 1005
Const MODE_NEWFILE = 1006

Sub Main()
    Dim fh As Long, s As String, mem As Long, n As Long
    s = "Hello, Amiga!"
    fh = Dos_Open("T:boing_test", MODE_NEWFILE)
    If fh = 0 Then Print "Can't create the file": Exit Sub
    n = Dos_Write(fh, StrPtr(s), Len(s))
    Dos_Close fh

    fh = Dos_Open("T:boing_test", MODE_OLDFILE)
    mem = AllocMem(64, True)
    n = Dos_Read(fh, mem, 64)
    Dos_Close fh
    Print n; "bytes: "; PeekS(mem, n)
    FreeMem mem
    Kill "T:boing_test"
End Sub
