Option Explicit
Dim ini As IniFile
Set ini = CreateObject("IniFile")
On Error Resume Next
ini.Value("Game", "lives=3") = 1
Print "bad key:"; Err.Number: Err.Clear
ini.Value("Game", "Title") = "two" & vbLf & "lines"
Print "line break:"; Err.Number: Err.Clear
ini.Load "no-such-file.ini", True
Print "must exist:"; Err.Number: Err.Clear
Set ini = CreateObject("IniFile")
ini.Save
Print "no name:"; Err.Number
