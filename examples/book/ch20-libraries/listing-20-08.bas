Option Explicit
Dim text As String, doc As Variant, k As Variant
text = "{""name"": ""Boing BASIC"", ""year"": 2026, ""tags"": [""BASIC"", ""AmigaOS 4""]," & _
       " ""author"": {""name"": ""Chris"", ""city"": null}, ""open"": true}"
doc = JsonParse(text)
Print doc("name"); " ("; doc("year"); ")"
Print "first tag: "; doc("tags")(0); ", tags:"; UBound(doc("tags")) + 1
Print "by "; doc("author")("name"); IIf(IsNull(doc("author")("city")), ", city unknown", "")
For Each k In doc
    Print k; " is a "; TypeName(doc(k))
Next
