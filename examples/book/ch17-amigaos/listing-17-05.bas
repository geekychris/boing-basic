Option Explicit

Declare Function Dos_Lock Lib "dos.library" Alias "#13" (ByVal name_ As String, ByVal type_ As Long) As Long
Declare Sub Dos_UnLock Lib "dos.library" Alias "#14" (ByVal lock_ As Long)
Declare Function IoErr Lib "dos.library" Alias "#21" () As Long

Const SHARED_LOCK = -2
Const ERROR_OBJECT_NOT_FOUND = 205

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
