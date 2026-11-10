' Main.bas - the menu of the console toolbox (exercise 1 of the Boing BASIC manual).
' Run it with:   boing run Console.bbp
' The random numbers are the same every run, so the game can be tested. Give the
' argument --random for a different game each time:   boing run Console.bbp --random
Option Explicit

Sub Main()
    Dim choice As String

    If InStr(Command(), "--random") > 0 Then
        Randomize                 ' seed from the clock: a new game every time
    Else
        Randomize 7               ' a fixed seed: the same numbers every run
    End If

    Print "Console Toolbox"
    Do
        Print
        Print "1) Guess the number"
        Print "2) Times-table quiz"
        Print "3) Count words"
        Print "0) Quit"
        choice = Ask("Your choice")
        Select Case choice
        Case "1": GuessGame
        Case "2": TablesQuiz
        Case "3": CountWords
        Case "0", "q", "Q": Exit Do
        Case Else: Print "Please type 0, 1, 2 or 3."
        End Select
    Loop
    Print "Goodbye!"
End Sub
