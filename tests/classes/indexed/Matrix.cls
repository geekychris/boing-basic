Private cells() As Double
Private mRows As Long, mCols As Long
Public Sub Init(ByVal rows As Long, ByVal cols As Long)
    mRows = rows: mCols = cols
    ReDim cells(1 To rows, 1 To cols)
End Sub
Public Property Get Cell(ByVal r As Long, ByVal c As Long) As Double
    Cell = cells(r, c)
End Property
Public Property Let Cell(ByVal r As Long, ByVal c As Long, ByVal v As Double)
    cells(r, c) = v
End Property
Public Function Times(other As Matrix) As Matrix
    Dim m As New Matrix, i As Long, j As Long, k As Long, s As Double
    m.Init mRows, other.Cols
    For i = 1 To mRows
        For j = 1 To other.Cols
            s = 0
            For k = 1 To mCols
                s = s + cells(i, k) * other.Cell(k, j)
            Next
            m.Cell(i, j) = s
        Next
    Next
    Set Times = m
End Function
Public Property Get Cols() As Long
    Cols = mCols
End Property
