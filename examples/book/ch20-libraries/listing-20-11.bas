Option Explicit
Dim settings As Variant, recent As Variant
settings = JsonParse("{""volume"": 48, ""recent"": [""RAM:a.txt"", ""RAM:b.txt""]}")
settings("volume") = settings("volume") + 16
recent = settings("recent")                ' a copy of the array
ReDim Preserve recent(UBound(recent) + 1)
recent(UBound(recent)) = "RAM:c.txt"
settings("recent") = recent                ' put the changed copy back
settings("saved") = #2026-11-10 08:45:00#
Print JsonStringify(settings)
