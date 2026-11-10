' main.bas - WordFreq: the five most common words of a text, and all the counts as JSON.
'   boing run wordfreq.bbp            print the report and the JSON
'   boing run wordfreq.bbp RAM:w.json also save the JSON in that file
Option Explicit

Sub Main()
    Dim text As String, counts As Dictionary, top As Variant, i As Long
    Dim report As StringBuilder, doc As Dictionary, entry As Dictionary, list() As Variant
    Dim json As String, f As Integer

    text = "The Amiga was the computer of the future. The future came, and the Amiga " & _
           "is still here: people write programs for the Amiga, and the programs run on " & _
           "the Amiga as they did, only faster. Write one more program, and run it."

    Set counts = CountWords(text)
    top = TopWords(counts, 5)

    ' the report: many small pieces, so a StringBuilder
    Set report = CreateObject("StringBuilder")
    report.Append("Words: ").Append(TotalWords(counts)).Append(", different: ").AppendLine counts.Count
    report.AppendLine "Most common:"
    For i = 0 To UBound(top)
        report.Append Right("   " & counts(top(i)), 3), "  ", top(i)
        report.AppendLine
    Next
    Print report.ToString;

    ' the document: {"words": n, "different": n, "top": [{"word": .., "count": ..}, ...], "counts": {...}}
    Set doc = CreateObject("Dictionary")
    doc("words") = TotalWords(counts)
    doc("different") = counts.Count
    ReDim list(UBound(top))
    For i = 0 To UBound(top)
        Set entry = CreateObject("Dictionary")
        entry("word") = top(i)
        entry("count") = counts(top(i))
        Set list(i) = entry
    Next
    doc("top") = list
    Set doc("counts") = counts
    json = JsonStringify(doc, 2)

    If Command() <> "" Then
        f = FreeFile
        Open Command() For Output As #f
        Print #f, json
        Close #f
        Print "Saved the counts in "; Command()
    Else
        Print "As JSON: "; JsonStringify(doc("top"))
        Print "(give a file name to save all"; counts.Count; "counts)"
    End If
End Sub
