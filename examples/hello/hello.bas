' Hello - a console program.  boing run hello.bas   /   boing build hello.bas
Option Explicit

Dim name As String, i As Integer

Print "Hello from Boing BASIC on "; Environ("Workbench"); "!"
Print "Running from "; App.Path
If Command() <> "" Then Print "Arguments: "; Command()

For i = 1 To 3
    Print "Boing"; String(i, "!")
Next i

name = InputBox("What's your name?", "Hello", "Amiga user")
If name <> "" Then MsgBox "Hello, " & name & "!", vbInformation, "Hello"
