' dicttest.bas - Boing.Dictionary
Option Explicit

Dim d As Dictionary, e As Dictionary, k As Variant, v As Variant, i As Long, s As String, ks As Variant
Dim o1 As Collection, o2 As Collection

Set d = CreateObject("Dictionary")
Print TypeName(d), d.Count

' Add, Item (default member), Exists, Count
d.Add "apple", 3
d.Add "pear", 5
d("plum") = 7                       ' assigning adds
d("apple") = 4                      ' ... or replaces
Print d.Count, d("apple"), d.Item("pear"), d("plum")
Print d.Exists("pear"), d.Exists("PEAR"), d.Exists("kiwi")
Print IsEmpty(d("kiwi")), d.Count   ' a missing key reads as Empty and isn't added

' insertion order for For Each, Keys and Items
For Each k In d
    s = s & k & "=" & d(k) & " "
Next
Print s
ks = d.Keys
Print LBound(ks), UBound(ks), ks(0), ks(2)
v = d.Items
Print v(0) + v(1) + v(2)

' Remove keeps the order of the rest
d.Remove "pear"
s = ""
For Each k In d: s = s & k & " ": Next
Print s; d.Count

' numbers: 1, 1&, 1# and True-ish values are one key per value; "1" is different
Set e = CreateObject("Dictionary")
e(1) = "one"
e(1&) = "uno"
e(2.5) = "two and a half"
e("1") = "string one"
Print e.Count, e(1), e(1#), e(2.5), e("1")

' objects are keys by identity
Set o1 = New Collection: Set o2 = New Collection
e(o1) = "first": e(o2) = "second"
Print e(o1), e(o2), e.Count

' values can be objects and arrays
Set e("child") = CreateObject("Dictionary")
e("child")("x") = 42
Print e("child")("x"), TypeName(e("child"))
e("list") = Array(10, 20, 30)
Print e("list")(1)

' CompareMode = 1: case-insensitive string keys
Dim c As Dictionary
Set c = CreateObject("Dictionary")
c.CompareMode = 1
c("Amiga") = 1200
Print c("AMIGA"), c.Exists("amiga"), c.CompareMode

' renaming a key keeps its value and place
d.Key("apple") = "APPLE"
s = ""
For Each k In d: s = s & k & "=" & d(k) & " ": Next
Print s

' errors
On Error Resume Next
d.Add "plum", 1
Print "Add existing:"; Err.Number
Err.Clear
d.Remove "nothing"
Print "Remove missing:"; Err.Number
Err.Clear
c.CompareMode = 0
Print "CompareMode when not empty:"; Err.Number
Err.Clear
d(Null) = 1
Print "Null key:"; Err.Number
On Error GoTo 0

' many keys: growth, removal, compaction
Set e = CreateObject("Dictionary")
For i = 1 To 20000: e("k" & i) = i: Next
For i = 1 To 20000 Step 2: e.Remove "k" & i: Next
For i = 20001 To 25000: e("k" & i) = i: Next
Dim sum As Double, okay As Boolean
okay = True
For i = 2 To 20000 Step 2
    If e("k" & i) <> i Then okay = False
Next
For Each k In e: sum = sum + e(k): Next
Print e.Count, okay, sum, e.Exists("k1"), e.Exists("k25000")

d.RemoveAll
Print d.Count, d.Exists("plum")
