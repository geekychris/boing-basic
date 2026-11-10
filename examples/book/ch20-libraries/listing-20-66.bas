Option Explicit
Dim prefs As IniFile, s As Variant, k As Variant, runs As Long, i As Long

Set prefs = CreateObject("IniFile")
' start from a file with a comment in it, written by "the user"
prefs.LoadText "; settings for the counter" & vbLf & "[User]" & vbLf & "Name = Ann" & vbLf
prefs.Save "counter.ini"

For i = 1 To 3                                 ' three "runs" of the program
    Set prefs = CreateObject("IniFile")
    If Not prefs.Load("counter.ini") Then Print "first run"
    runs = CLng(prefs.Value("Stats", "Runs", "0")) + 1
    prefs.Value("Stats", "Runs") = runs
    prefs.Save
Next

Print "Hello "; prefs("User", "Name"); ", run"; runs
Print "Colour: "; prefs.Value("User", "Colour", "blue")
For Each s In prefs.Sections
    For Each k In prefs.Keys(s)
        Print "["; s; "] "; k; " = "; prefs.Value(s, k)
    Next
Next
Print "---"
Print prefs.Text;
Kill "counter.ini"
