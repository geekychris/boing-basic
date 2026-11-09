' Variables declared As one of the runtime's classes (Engine3D, Canvas, Audio): members checked
' when compiling, called by id at run time; a mismatched object is error 13 on Set
Sub Main()
    Dim e As Engine3D, cv As Boing.Canvas, au As Audio, o As Object, x As Long, i As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 48
    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv
    For i = 1 To 1000
        x = x Xor e.Hash(i)
    Next
    Print x; cv.Width; cv.Height; TypeName(e); TypeName(cv)
    Set o = e
    Print "late"; o.Hash(1000) = e.Hash(1000)
    Set au = CreateObject("Boing.Audio")
    Print TypeName(au)
    Print "nothing"; e Is Nothing; o Is e
    On Error Resume Next
    Set cv = o
    Print "set mismatch"; Err.Number
    Err.Clear
    Set e = Nothing
    x = e.Hash(1)
    Print "nothing call"; Err.Number
End Sub
