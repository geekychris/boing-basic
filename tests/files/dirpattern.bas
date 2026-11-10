' Dir and Kill with AmigaDOS patterns (#?) as well as * and ?; no "." / ".." with vbDirectory
Sub Main()
    Dim f As Integer, n As String, c As Long
    MkDir "dsub"
    f = FreeFile: Open "a1.txt" For Output As #f: Close #f
    f = FreeFile: Open "a22.txt" For Output As #f: Close #f
    f = FreeFile: Open "b1.dat" For Output As #f: Close #f
    n = Dir("a#?.txt")
    Do While n <> "": c = c + 1: n = Dir: Loop
    Print "a#?.txt"; c
    c = 0: n = Dir("#?.dat"): Do While n <> "": c = c + 1: n = Dir: Loop
    Print "#?.dat"; c
    c = 0: n = Dir("a#2.txt"): Do While n <> "": c = c + 1: n = Dir: Loop
    Print "a#2.txt"; c
    c = 0: n = Dir("*", vbDirectory)
    Do While n <> ""
        If n = "." Or n = ".." Then Print "dot!"
        If n = "dsub" Then c = c + 1
        n = Dir
    Loop
    Print "dsub listed"; c
    Kill "a#?.txt"
    Print "after kill "; Dir("a*.txt") = ""
    Kill "b1.dat"
    RmDir "dsub"
End Sub
