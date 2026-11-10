' wordcount.bas - count the words of a text file with a Dictionary and show the most common.
'   boing run wordcount.bas FILE [TOP]
Option Explicit

Dim counts As Dictionary, fname As String, top As Long, args() As String
Dim f As Integer, line_ As String, w As String, ch As String, i As Long
Dim k As Variant, words As Variant, n As Long, j As Long, t As Variant

args = Split(Command(), " ")
If UBound(args) < 0 Then Print "usage: wordcount FILE [TOP]": End
fname = args(0)
top = 10
If UBound(args) >= 1 Then top = Val(args(1))

Set counts = CreateObject("Dictionary")
counts.CompareMode = 1                  ' "The" and "the" are one word
f = FreeFile
Open fname For Input As #f
Do While Not EOF(f)
    Line Input #f, line_
    w = ""
    For i = 1 To Len(line_) + 1
        ch = Mid(line_, i, 1)
        If ch Like "[A-Za-z'0-9]" Then
            w = w & ch
        ElseIf w <> "" Then
            counts(w) = counts(w) + 1   ' a missing key reads as Empty, and Empty + 1 = 1
            w = ""
        End If
    Next
Loop
Close #f

' the words, sorted by count (a simple selection sort of the top entries)
words = counts.Keys
n = UBound(words) + 1
If top > n Then top = n
For i = 0 To top - 1
    For j = i + 1 To n - 1
        If counts(words(j)) > counts(words(i)) Then t = words(i): words(i) = words(j): words(j) = t
    Next
    Print Right(Space(6) & counts(words(i)), 6); "  "; words(i)
Next
Print n; "different words"
