' jsontest.bas - JsonParse / JsonStringify
Option Explicit

Dim v As Variant, s As String, d As Dictionary, c As Collection, a As Variant, i As Long, k As Variant

' scalars
Print TypeName(JsonParse("42")), JsonParse("42"), JsonParse("-7")
Print TypeName(JsonParse("2147483648")), JsonParse("2147483648")
Print TypeName(JsonParse("3.5")), JsonParse("3.5"), JsonParse("1e3"), JsonParse("-2.5E-2")
Print JsonParse("true"), JsonParse("false"), IsNull(JsonParse("null"))
Print JsonParse("""plain"""), Len(JsonParse(""""""))

' escapes and Unicode (\u written as UTF-8)
s = JsonParse("""tab\there \""q\"" back\\slash \/ nl\nend""")
Print Replace(Replace(s, vbTab, "<TAB>"), vbLf, "<LF>")
s = JsonParse("""é€😀""")
For i = 1 To Len(s): Print Hex(Asc(Mid(s, i, 1))); " ";: Next
Print

' objects and arrays
v = JsonParse(" { ""a"" : 1 , ""b"" : [ 1 , [ 2 , 3 ] , { ""c"" : ""d"" } ] , ""e"" : { } , ""f"" : [ ] } ")
Print TypeName(v), v.Count, v("a"), UBound(v("b")), v("b")(1)(1), v("b")(2)("c")
Print TypeName(v("e")), v("e").Count, UBound(v("f"))
For Each k In v: Print k;: Next
Print

' stringify
Print JsonStringify(v)
Set d = CreateObject("Dictionary")
d("text") = "line1" & vbLf & "say ""hi"" \ " & Chr(1)
d("int") = 12
d("dbl") = 0.1
d("big") = 1E+20
d("neg") = -3.75
d("t") = True
d("n") = Null
d("e") = Empty
d("arr") = Array(1, "two", 3.5)
d(7) = "numeric key"
d("date") = DateSerial(1985, 7, 23) + TimeSerial(10, 30, 5)
Set c = New Collection
c.Add "x": c.Add 2
Set d("coll") = c
s = JsonStringify(d)
Print s
' and back
v = JsonParse(s)
Print v("text") = d("text"), v("int"), v("dbl"), v("big"), v("t"), IsNull(v("n")), IsNull(v("e")), v("arr")(1), v("7"), v("date"), v("coll")(0)
Print JsonStringify(Array(), 2), JsonStringify(CreateObject("Dictionary"), 2)
Print JsonStringify(JsonParse("[1,{""a"":[true,false]}]"), 1)

' a round trip of a larger document
s = "["
For i = 1 To 500
    s = s & "{""id"":" & i & ",""name"":""item " & i & """,""ok"":" & IIf(i Mod 2, "true", "false") & "}"
    If i < 500 Then s = s & ","
Next
s = s & "]"
v = JsonParse(s)
Print UBound(v), v(499)("name"), v(0)("ok"), JsonStringify(v) = s

' parse errors: 31201 with the position
On Error Resume Next
v = JsonParse("{""a"": 1,}")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("[1, 2")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("{""a"": tru}")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("1 2")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("""abc")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("{" & vbLf & "  ""x"": 01}")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("")
Print Err.Number; Err.Description
Err.Clear
' values that can't be written: 31202
Dim h As Http
Set h = CreateObject("Http")
s = JsonStringify(h)
Print Err.Number; Err.Description
Err.Clear
Dim m(1, 1) As Long
s = JsonStringify(m)
Print Err.Number; Err.Description
Err.Clear
Set d = CreateObject("Dictionary")
Set d("me") = d
s = JsonStringify(d)
Print Err.Number; Left(Err.Description, 30)
d.RemoveAll
Err.Clear
s = JsonStringify(1, 99)
Print Err.Number
