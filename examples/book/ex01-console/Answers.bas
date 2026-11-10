' Answers.bas - reading the user's answers.
Option Explicit

' Ask a question and return the answer without spaces round it.
Public Function Ask(prompt As String) As String
    Dim answer As String
    Print prompt & ": ";          ' the ; keeps the cursor on this line
    Line Input answer
    Ask = Trim(answer)
End Function

' Ask until the answer is a whole number from low to high.
Public Function AskNumber(prompt As String, low As Long, high As Long) As Long
    Dim answer As String
    Do
        answer = Ask(prompt)
        If IsNumeric(answer) Then
            If Val(answer) >= low And Val(answer) <= high And Val(answer) = Int(Val(answer)) Then
                AskNumber = Val(answer)
                Exit Function
            End If
        End If
        Print "Please type a whole number from " & low & " to " & high & "."
    Loop
End Function

' A random whole number from low to high.
Public Function RandomNumber(low As Long, high As Long) As Long
    RandomNumber = Int(Rnd * (high - low + 1)) + low
End Function
