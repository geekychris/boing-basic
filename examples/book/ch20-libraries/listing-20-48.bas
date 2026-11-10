Option Explicit
Dim re As RegExp, parts As Variant
Set re = CreateObject("RegExp")
re.Pattern = "\s*[,;]\s*"
parts = re.Split("apples, pears;plums ,  cherries")
Print UBound(parts) + 1; " pieces: "; Join(parts, "|")
re.Pattern = "(-)"                      ' a group: the dashes are pieces too
Print Join(re.Split("1-2-3"), "|")

Print re.Escape("1+1=2? (yes) $5.00")
re.Pattern = re.Escape("1+1=2?")
Print re.Test("is 1+1=2?"); re.Test("11=2")
