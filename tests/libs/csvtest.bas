' Csv: reading (quotes, line breaks, headers, delimiters), writing, ParseLine/FormatRecord, ReadAll
Option Explicit
Dim rd As Csv, s As String, a, i As Long, j As Long, w As Csv

Set rd = CreateObject("Csv")
s = "name,age,city" & vbCrLf & _
    "Ann,34,""Bonn, Germany""" & vbCrLf & _
    """Bob """"B"""" Smith"",41," & vbLf & _
    vbLf & _
    "Cy,7,""two" & vbLf & "lines""" & vbCr & _
    "Dee,,"
rd.HasHeader = True
rd.LoadText s
Print "headers:"; Join(rd.Headers, "|"); " age column"; rd.ColumnIndex("AGE")
Do While rd.ReadRecord()
    Print rd.RecordNumber; rd.LineNumber; rd.FieldCount; " ["; rd.Field("name"); "] ["; rd.Field(1); "] ["; Replace(rd.Field("City"), vbLf, "\n"); "]"
Loop
Print "at end:"; rd.AtEnd; rd.ReadRecord(); rd.FieldCount

' no header, other delimiter, quote off, trimming
Set rd = CreateObject("Csv")
rd.Delimiter = ";"
rd.LoadText "1; 2 ;3" & vbLf & "a;""b;c"";d"
rd.ReadRecord: Print Join(rd.Fields, "|")
rd.ReadRecord: Print Join(rd.Fields, "|")
rd.TrimFields = True
rd.LoadText "1; 2 ;3"
rd.ReadRecord: Print Join(rd.Fields, "|")
rd.Quote = ""
rd.LoadText "a;""b;c"""
rd.ReadRecord: Print Join(rd.Fields, "|"); rd.FieldCount
rd.Delimiter = vbTab: rd.Quote = """"
Print Join(rd.ParseLine("x" & vbTab & """y" & vbTab & "z""" & vbTab), "|"); UBound(rd.ParseLine("x" & vbTab & "y" & vbTab))

' ReadAll: a 2-D array, short records padded
Set rd = CreateObject("Csv")
rd.LoadText Chr(239) & Chr(187) & Chr(191) & "a,b,c" & vbLf & "1,2" & vbLf & "x,y,z,extra"
a = rd.ReadAll()
Print "ReadAll:"; UBound(a, 1); UBound(a, 2)
For i = 0 To UBound(a, 1)
    For j = 0 To UBound(a, 2): Print "["; a(i, j); "]";: Next
    Print
Next

' writing: quoting only when needed, QuoteAll, numbers/dates/Null, arrays
Set w = CreateObject("Csv")
Print w.FormatRecord("plain", "with,comma", "with ""quote""", " lead", "multi" & vbLf & "line", 3.5, True, Null, "")
w.QuoteAll = True
Print w.FormatRecord(Array("a", 1, Empty))
w.QuoteAll = False
w.Delimiter = ";"
Print w.FormatRecord(Array("x;y", "z"))
w.Delimiter = ","
w.WriteRecord "id", "text"
w.WriteRecord 1, "a, b"
w.LineEnding = vbCrLf
w.WriteRecord Array(2, "c")
Print Replace(Replace(w.Text, vbCr, "\r"), vbLf, "\n")
w.Text = ""
Print "[" & w.Text & "]"

' files: write, append, read back (round trip of awkward values)
w.LineEnding = vbLf
w.Create "csvtest.tmp"
w.WriteRecord "k", "v"
w.WriteRecord "quote", "say ""hi"""
w.Close
w.Create "csvtest.tmp", True
w.WriteRecord "nl", "a" & vbLf & "b"
w.WriteRecord "bin", "x" & Chr(0) & "y"
w.Close
Set rd = CreateObject("Csv")
rd.HasHeader = True
rd.Open "csvtest.tmp"
Do While rd.ReadRecord()
    s = rd.Field("v")
    Print rd.Field("k"); "="; Len(s); " "; Replace(Replace(s, vbLf, "\n"), Chr(0), "\0")
Loop
rd.Close
Kill "csvtest.tmp"

' errors
On Error Resume Next
rd.Delimiter = ",,"
Print "delimiter:"; Err.Number: Err.Clear
rd.Quote = ","
Print "same:"; Err.Number: Err.Clear
rd.Open "no such file.rd"
Print "open:"; Err.Number: Err.Clear
rd.HasHeader = True
rd.LoadText "a,b" & vbLf & "1,2"
rd.ReadRecord
s = rd.Field("c")
Print "column:"; Err.Number; " "; Err.Description: Err.Clear
Print "short:["; rd.Field(5); "]"; Err.Number
