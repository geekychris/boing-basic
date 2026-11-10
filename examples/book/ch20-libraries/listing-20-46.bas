Option Explicit
Dim re As RegExp, text As String
Set re = CreateObject("RegExp")
re.Pattern = "amiga"
Print re.Test("AMIGA forever");
re.IgnoreCase = True
Print re.Test("AMIGA forever")

text = "one" & vbLf & "two" & vbLf & "three"
re.Pattern = "^\w+$"
re.Global = True
Print re.Execute(text).Count;          ' the whole text isn't one word
re.MultiLine = True
Print re.Execute(text).Count           ' but each line is
Print re.Replace(text, "* $&")
