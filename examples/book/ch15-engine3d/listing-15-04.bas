Option Explicit

Sub Main()
    Dim e As Engine3D, m As Long, t As Long, f As Integer
    Set e = CreateObject("Boing.Engine3D")
    ' write a small model file: a square pyramid by hand, and a box from a builder
    f = FreeFile
    Open "tent.3d" For Output As #f
    Print #f, "# a tent: four sides and a floor"
    Print #f, "v -40 0 -40"
    Print #f, "v  40 0 -40"
    Print #f, "v  40 0  40"
    Print #f, "v -40 0  40"
    Print #f, "v   0 60  0     # the top (index 4)"
    Print #f, "f 2 0 4 1"
    Print #f, "f 3 1 4 2"
    Print #f, "f 2 2 4 3"
    Print #f, "f 3 3 4 0"
    Print #f, "f body 0 1 2 3"
    Print #f, "box 5 6 -10 10 0 20 -50 -40"
    Close #f
    m = e.ModelLoad("tent.3d")
    Print "model"; m; ":"; e.ModelVerts(m); "vertices,"; e.ModelFaces(m); "faces, radius"; e.ModelRadius(m)
    t = e.ModelNew()
    Print "next model is"; t
    e.ModelFree m
    Kill "tent.3d"
End Sub
