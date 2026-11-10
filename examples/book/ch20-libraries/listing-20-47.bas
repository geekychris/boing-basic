Option Explicit
Dim re As RegExp
Set re = CreateObject("RegExp")
re.Pattern = "(\w+)@(\w+)"
re.Global = True
Print re.Replace("ann@boing bob@amiga", "$2:$1")
Print re.Replace("ann@boing", "[$$][$&][$`][$'][$3]")
re.Pattern = "\d"
Print re.Replace("a1b2c3", "#")
re.Global = False
Print re.Replace("a1b2c3", "#")         ' only the first
re.Global = True
re.Pattern = "\s+"
Print re.Replace("too    many     spaces", " ")
