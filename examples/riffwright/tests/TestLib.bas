' Riffwright tests - helpers
Option Explicit

Public Function ReadAll(ByVal path As String) As Variant
    Dim b() As Byte, f As Integer
    ReDim b(0 To FileLen(path) - 1)
    f = FreeFile
    Open path For Binary Access Read As #f
    Get #f, , b
    Close #f
    ReadAll = b
End Function

' "same" or where the files first differ
Public Function CompareFiles(ByVal a As String, ByVal b As String) As String
    Dim x As Variant, y As Variant, i As Long, n As Long
    x = ReadAll(a): y = ReadAll(b)
    If UBound(x) <> UBound(y) Then CompareFiles = "size " & (UBound(x) + 1) & " vs " & (UBound(y) + 1): Exit Function
    n = UBound(x)
    For i = 0 To n
        If x(i) <> y(i) Then CompareFiles = "differ at " & i: Exit Function
    Next i
    CompareFiles = "same"
End Function

Public Sub Check(ByVal what As String, ByVal ok As Boolean)
    If ok Then Print "ok   "; what Else Print "FAIL "; what
End Sub
