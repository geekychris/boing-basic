Option Explicit
Dim re As RegExp
Set re = CreateObject("RegExp")
re.Pattern = "<.+>":  Print re.FirstMatch("<b>bold</b>")    ' greedy: as much as possible
re.Pattern = "<.+?>": Print re.FirstMatch("<b>bold</b>")    ' lazy: as little as possible
re.Pattern = "\w+(?=!)": Print re.FirstMatch("hello there!")
re.Pattern = "\b(\w+) \1\b": Print re.FirstMatch("this is is a typo")
re.Pattern = "^\d{3}-\d{4}$": Print re.Test("555-1234"); re.Test("555-12345")
