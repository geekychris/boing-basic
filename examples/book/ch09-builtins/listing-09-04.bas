Dim s As String
s = "one two one two"
Print InStr(s, "two"); InStr(6, s, "two"); InStr(s, "three"); InStr(s, "TWO")
Print InStr(1, s, "TWO", vbTextCompare)
Print InStrRev(s, "one"); InStrRev(s, "one", 8)
Print StrComp("apple", "banana"); StrComp("pear", "pear"); StrComp("Zoo", "apple")
Print StrComp("Zoo", "apple", vbTextCompare)
