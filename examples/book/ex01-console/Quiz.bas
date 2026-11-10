' Quiz.bas - a times-table quiz: five questions from one table.
Option Explicit

Const QUESTIONS = 5

Public Sub TablesQuiz()
    Dim table As Long, i As Long, n As Long, answer As Long, score As Long

    table = AskNumber("Which table (2 to 12)", 2, 12)
    For i = 1 To QUESTIONS
        n = RandomNumber(2, 12)
        answer = AskNumber("Question" & Str(i) & ": " & n & " x " & table, 0, 1000)
        If answer = n * table Then
            Print "Right!"
            score = score + 1
        Else
            Print "No,"; n; "x"; table; "="; n * table
        End If
    Next i
    Print "You scored"; score; "out of"; QUESTIONS; "- "; Praise(score)
End Sub

Private Function Praise(score As Long) As String
    Select Case score
    Case QUESTIONS: Praise = "perfect!"
    Case Is >= QUESTIONS - 1: Praise = "well done."
    Case Is >= QUESTIONS \ 2: Praise = "not bad."
    Case Else: Praise = "keep practising."
    End Select
End Function
