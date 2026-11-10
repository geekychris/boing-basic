' a name with # that exists is that file (Dir and Kill); with * or ? it is a pattern
Sub Main()
    Dim f As Integer
    f = FreeFile: Open "track#1.mod" For Output As #f: Close #f
    f = FreeFile: Open "track11.mod" For Output As #f: Close #f
    Print Dir("track#1.mod")
    Kill "track#1.mod"
    Print "after kill: "; Dir("track11.mod"); " ["; Dir("track#1.mod"); "]"
    Print Dir("track#?.mod")
    Kill "track#?.mod"
    Print "left ["; Dir("track#?.mod"); "]"
End Sub
