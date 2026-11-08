' Conway's Game of Life on a small torus: a glider and a blinker
Option Explicit
Const W = 12, H = 6
Dim grid(0 To W - 1, 0 To H - 1) As Boolean, nxt(0 To W - 1, 0 To H - 1) As Boolean

Sub SetCells(ByVal cells As String)
    Dim parts() As String, i As Integer, xy() As String
    parts = Split(cells, ";")
    For i = 0 To UBound(parts)
        xy = Split(parts(i), ",")
        grid(CInt(xy(0)), CInt(xy(1))) = True
    Next
End Sub

Function Neighbours(ByVal x As Integer, ByVal y As Integer) As Integer
    Dim dx As Integer, dy As Integer, n As Integer
    For dy = -1 To 1
        For dx = -1 To 1
            If dx <> 0 Or dy <> 0 Then
                If grid((x + dx + W) Mod W, (y + dy + H) Mod H) Then n = n + 1
            End If
        Next
    Next
    Neighbours = n
End Function

Sub Generation()
    Dim x As Integer, y As Integer, n As Integer
    For y = 0 To H - 1
        For x = 0 To W - 1
            n = Neighbours(x, y)
            nxt(x, y) = (n = 3) Or (grid(x, y) And n = 2)
        Next
    Next
    For y = 0 To H - 1
        For x = 0 To W - 1
            grid(x, y) = nxt(x, y)
        Next
    Next
End Sub

Sub Show(ByVal gen As Integer)
    Dim x As Integer, y As Integer, line As String, alive As Integer
    Print "gen"; gen
    For y = 0 To H - 1
        line = ""
        For x = 0 To W - 1
            If grid(x, y) Then line = line & "#": alive = alive + 1 Else line = line & "."
        Next
        Print line
    Next
    Print "alive:"; alive
End Sub

SetCells "1,0;2,1;0,2;1,2;2,2;8,4;9,4;10,4"
Dim g As Integer
For g = 0 To 4
    If g = 0 Or g = 4 Then Show g
    Generation
Next
