Option Explicit
Dim re As RegExp, m As Variant, ms As Variant, text As String
Set re = CreateObject("RegExp")
re.Pattern = "(\w+)@([\w.]+)"
re.Global = True
text = "write to ann@boing.org or bob@amiga.net"
Set ms = re.Execute(text)
Print ms.Count; " addresses"
For Each m In ms
    Print m.SubMatches(0); " at "; m.SubMatches(1); ", position"; m.FirstIndex; ", length"; m.Length
    Print "  Mid gives: "; Mid(text, m.FirstIndex + 1, m.Length)
Next
Print "the first: "; ms(0); ", its domain from"; ms(0).SubMatchIndex(1)
