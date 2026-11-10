Option Explicit
Dim doc As XmlDocument, bad As Variant, i As Long
Set doc = CreateObject("XmlDocument")
bad = Array("<a><b></a>", "<a b=1/>", "<a/><b/>", "")
On Error Resume Next
For i = 0 To UBound(bad)
    doc.LoadXml bad(i)
    Print Err.Number; Err.Description
    Err.Clear
Next
doc.LoadXml "<a/>"
doc.Root.AddElement "two words"
Print Err.Number; Err.Description
