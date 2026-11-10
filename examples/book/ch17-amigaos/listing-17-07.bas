Option Explicit
#Include "dos.bi"           ' Dos_Lock, Dos_UnLock, IoErr, SHARED_LOCK, ERROR_OBJECT_NOT_FOUND

Sub Main()
    Dim lk As Long, e As Long
    e = IoErr()                                   ' opens dos.library
    lk = Dos_Lock("RAM:no such file", SHARED_LOCK): e = IoErr()
    If lk = 0 Then
        If e = ERROR_OBJECT_NOT_FOUND Then Print "Not found" Else Print "Error"; e
    Else
        Dos_UnLock lk
        Print "It exists"
    End If
End Sub
