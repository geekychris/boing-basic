Option Explicit
Dim item As Variant, created As Date
item = JsonParse("{""created_at"": ""2026-11-10T08:45:00Z""}")
created = UtcToLocal(ParseIso8601(item("created_at")))
Print "Created "; Format(created, "dd.mm.yyyy hh:nn")
