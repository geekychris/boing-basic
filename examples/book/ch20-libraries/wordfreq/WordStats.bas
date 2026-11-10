' WordStats.bas - counting words with a Dictionary
Option Explicit

' the words of text (letters, digits and ') in lower case, with how often each comes
Public Function CountWords(text As String) As Dictionary
    Dim counts As Dictionary, i As Long, ch As String, w As String
    Set counts = CreateObject("Dictionary")
    For i = 1 To Len(text) + 1
        ch = Mid(text, i, 1)
        If ch Like "[A-Za-z0-9']" Then
            w = w & LCase(ch)
        ElseIf w <> "" Then
            counts(w) = counts(w) + 1       ' a missing key reads as Empty: Empty + 1 = 1
            w = ""
        End If
    Next
    Set CountWords = counts
End Function

' the total of all the counts
Public Function TotalWords(counts As Dictionary) As Long
    Dim k As Variant, n As Long
    For Each k In counts
        n = n + counts(k)
    Next
    TotalWords = n
End Function

' the n most common words, most common first; words with the same count keep their order
Public Function TopWords(counts As Dictionary, n As Long) As Variant
    Dim rest As Dictionary, k As Variant, best As Variant, i As Long, result() As Variant
    Set rest = CreateObject("Dictionary")
    For Each k In counts
        rest(k) = counts(k)
    Next
    If n > rest.Count Then n = rest.Count
    If n = 0 Then TopWords = Array(): Exit Function
    ReDim result(n - 1)
    For i = 0 To n - 1
        best = Empty
        For Each k In rest
            If IsEmpty(best) Then
                best = k
            ElseIf rest(k) > rest(best) Then
                best = k
            End If
        Next
        result(i) = best
        rest.Remove best
    Next
    TopWords = result
End Function
