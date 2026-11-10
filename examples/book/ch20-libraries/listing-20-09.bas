Option Explicit
Dim word As String
word = JsonParse("""caf\u00e9""")      ' the JSON text "caf\u00e9"
Print Len(word); " bytes; as Latin-1:"; Len(Utf8Decode(word)); " characters"
