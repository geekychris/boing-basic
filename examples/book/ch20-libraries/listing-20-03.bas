Option Explicit
Dim d As Dictionary, k As Variant, keys As Variant, values As Variant

Set d = CreateObject("Dictionary")
d.Add "A500", 1987
d.Add "A1200", 1992
d("A4000") = 1992
d("CD32") = 1993

Print d.Exists("A1200"), d.Exists("A600")
Print IsEmpty(d("A600")), d.Count         ' reading a missing key doesn't add it

d.Remove "CD32"
d.Key("A500") = "Amiga 500"               ' renamed, still in the first place

keys = d.Keys
values = d.Items
Print UBound(keys) + 1; "models, first: " & keys(0) & " (" & values(0) & ")"
For Each k In d
    Print k, d(k)
Next
d.RemoveAll
Print d.Count
