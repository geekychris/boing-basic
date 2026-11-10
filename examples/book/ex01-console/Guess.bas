' Guess.bas - guess the number from 1 to 100.
Option Explicit

Public Sub GuessGame()
    Dim secret As Long, guess As Long, tries As Long

    secret = RandomNumber(1, 100)
    Print "I am thinking of a number from 1 to 100."
    Do
        guess = AskNumber("Your guess", 1, 100)
        tries = tries + 1
        If guess = secret Then Exit Do
        If guess < secret Then Print "Too low"; Else Print "Too high";
        Print " - "; Hint(Abs(guess - secret))
    Loop
    Print "Yes, it was"; secret; "- you needed"; tries; "tries. "; Rating(tries)
End Sub

' How close the guess is, in words.
Private Function Hint(distance As Long) As String
    Select Case distance
    Case 1 To 3: Hint = "very close!"
    Case 4 To 10: Hint = "close."
    Case 11 To 25: Hint = "not far."
    Case Else: Hint = "far away."
    End Select
End Function

' A comment on the number of tries.
Private Function Rating(tries As Long) As String
    Select Case tries
    Case 1: Rating = "Amazing luck!"
    Case 2 To 5: Rating = "Very good."
    Case 6, 7: Rating = "Good."
    Case Else: Rating = "Try halving the range each time."
    End Select
End Function
