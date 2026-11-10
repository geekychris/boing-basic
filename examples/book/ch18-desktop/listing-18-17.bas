' A second clipboard: unit 1 keeps its text while the user copies other things
Option Explicit
Dim kept As String

Clipboard.SetText "the user's text"
Clipboard.Unit = 1
Clipboard.SetText "a signature"
Clipboard.Unit = 0
Print Clipboard.GetText()

Clipboard.Unit = 1
If Clipboard.GetFormat(vbCFText) Then kept = Clipboard.GetText()
Clipboard.Unit = 0
Print kept
