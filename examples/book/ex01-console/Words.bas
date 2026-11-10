' Words.bas - count the lines, words and letters of some text, and find the longest word.
Option Explicit

Public Sub CountWords()
    Dim lineText As String, words() As String, w As String
    Dim i As Long, lines As Long, wordCount As Long, letters As Long
    Dim longest As String

    Print "Type some lines of text. An empty line ends the text."
    Do
        Line Input "> "; lineText
        If Trim(lineText) = "" Then Exit Do
        lines = lines + 1
        words = Split(lineText, " ")
        For i = 0 To UBound(words)
            w = CleanWord(words(i))
            If w <> "" Then                  ' two spaces in a row give an empty "word"
                wordCount = wordCount + 1
                letters = letters + Len(w)
                If Len(w) > Len(longest) Then longest = w
            End If
        Next i
    Loop

    Print "Lines:"; lines
    Print "Words:"; wordCount
    Print "Letters:"; letters
    If wordCount > 0 Then
        Print "Average word length: "; Format(letters / wordCount, "0.0")
        Print "Longest word: " & longest & " (" & Len(longest) & " letters)"
    End If
End Sub

' The word in lower case, with only its letters, digits and apostrophes kept.
Private Function CleanWord(word As String) As String
    Dim i As Long, c As String
    For i = 1 To Len(word)
        c = Mid(word, i, 1)
        Select Case LCase(c)
        Case "a" To "z", "0" To "9", "'": CleanWord = CleanWord & LCase(c)
        End Select
    Next i
End Function
