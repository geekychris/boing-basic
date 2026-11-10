Option Explicit
#Include "dos.bi"           ' Dos_Open, Dos_Close, Dos_Read, Dos_Write, MODE_OLDFILE, MODE_NEWFILE

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
