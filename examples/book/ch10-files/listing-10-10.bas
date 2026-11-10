Dim name As String, count As Integer, f As Integer

MkDir "pics"
f = FreeFile
Open "pics/boing.iff" For Output As #f: Close #f
Open "pics/notes.txt" For Output As #f: Close #f
MkDir "pics/old"

name = Dir("pics/*.IFF")
Do While name <> ""
    Print "picture: "; name
    name = Dir
Loop

name = Dir("pics/*", vbDirectory)
Do While name <> ""
    If name <> "." And name <> ".." Then count = count + 1
    name = Dir
Loop
Print count; "entries in pics"
Print "["; Dir("pics/old"); "] ["; Dir("pics/old", vbDirectory); "]"

Kill "pics/*.*"
RmDir "pics/old"
RmDir "pics"
