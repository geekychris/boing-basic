Option Explicit
Clipboard.SetText "for everyone"
Print Clipboard.HasText; " "; Clipboard.GetFormat(vbCFText); " "; Clipboard.GetFormat(vbCFBitmap)
Clipboard.Unit = 1                    ' a clipboard of the program's own
Print Clipboard.HasText
Clipboard.SetText "kept on unit 1"
Print Clipboard.GetText()
Clipboard.Unit = 0                    ' back to the shared clipboard
Print Clipboard.GetText()
