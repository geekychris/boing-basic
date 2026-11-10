Option Explicit
Dim user As Dictionary, address As Dictionary, seen As Dictionary
Dim a As New Collection, b As New Collection

Set user = CreateObject("Dictionary")
user("name") = "Ann"
Set address = CreateObject("Dictionary")
address("city") = "Amsterdam"
Set user("address") = address
user("address")("zip") = "1012"           ' changes the same Dictionary as address
user("langs") = Array("BASIC", "C")       ' arrays are stored as a copy

Print user("name"); " lives in "; address("city"); " "; user("address")("zip")
Print user("langs")(1), TypeName(user("address"))

' objects as keys: by identity
Set seen = CreateObject("Dictionary")
seen(a) = "first"
seen(b) = "second"
Print seen(a), seen(b), seen.Count
