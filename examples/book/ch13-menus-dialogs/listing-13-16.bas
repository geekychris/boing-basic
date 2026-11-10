Option Explicit
Clipboard.SetText "Boing!"
Print Clipboard.GetText()
Clipboard.Clear
Print "["; Clipboard.GetText(); "]"
