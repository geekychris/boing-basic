' array fields of Me used in hot loops (register forms / JIT)
Private Type Cell
    v As Long
    w As Single
End Type
Private px(0 To 99) As Long
Private m(1 To 4, 1 To 5) As Double
Private dyn() As Integer
Private cells(1 To 10) As Cell
Private flag(1 To 8) As Boolean
Public Sum As Long

Public Sub Fill(ByVal c As Long)
    Dim i As Long
    For i = 0 To 99
        px(i) = c + i
    Next
End Sub

Public Function Total() As Long
    Dim i As Long, t As Long
    For i = 0 To 99
        t = t + px(i)
    Next
    Total = t
End Function

Public Sub Grow(ByVal n As Long)
    Dim i As Long
    ReDim Preserve dyn(1 To n)
    For i = 1 To n
        dyn(i) = dyn(i) + i
    Next
End Sub

Public Function DynSum() As Long
    Dim i As Long, t As Long
    For i = LBound(dyn) To UBound(dyn)
        t = t + dyn(i)
    Next
    DynSum = t
End Function

Public Sub Mat()
    Dim i As Long, j As Long
    For i = 1 To 4
        For j = 1 To 5
            m(i, j) = i * 10 + j / 4
        Next
    Next
End Sub

Public Function MatAt(ByVal i As Long, ByVal j As Long) As Double
    MatAt = m(i, j)
End Function

Public Sub CellWork()
    Dim i As Long, k As Long
    For i = 1 To 1000
        k = (i Mod 10) + 1
        cells(k).v = cells(k).v + i
        cells(k).w = cells(k).w * 0.5! + 1
        flag((i Mod 8) + 1) = cells(k).v > 40000 Or flag((i Mod 8) + 1)
    Next
End Sub

Public Function CellInfo() As String
    Dim i As Long, s As String
    For i = 1 To 10
        s = s & cells(i).v & ":" & cells(i).w & " "
    Next
    For i = 1 To 8
        If flag(i) Then s = s & "T" Else s = s & "F"
    Next
    CellInfo = s
End Function

Public Sub Poke(ByVal i As Long, ByVal v As Long)
    px(i) = v
End Sub
