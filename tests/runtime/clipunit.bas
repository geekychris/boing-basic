' Clipboard.Unit, HasText, GetFormat (docs/ui.md) and App's locale formats (hosts: C locale)
Clipboard.SetText "unit zero"
Print Clipboard.Unit
Clipboard.Unit = 3
Print Clipboard.Unit
Print Clipboard.HasText
Print Clipboard.GetFormat(vbCFText)
Clipboard.SetText "unit three"
Print Clipboard.GetText
Print Clipboard.GetFormat(vbCFText), Clipboard.GetFormat(vbCFBitmap), Clipboard.GetFormat(vbCFRTF)
Clipboard.Unit = 0
Print Clipboard.GetText
On Error Resume Next
Clipboard.Unit = 256
Print Err.Number
Err.Clear
On Error GoTo 0
Print Clipboard.Unit
Print App.FormatNumber(1234567.891, 2)
Print App.FormatNumber(-42)
Print App.DecimalPoint; App.GroupSeparator
Print App.FormatNumber(-0.001)
Print Len(App.FormatNumber(1E+70, 2))
Print Right(App.FormatNumber(1E+70, 2), 7)
Print App.FormatDate(DateSerial(2026, 11, 10))
Print App.FormatDate(DateSerial(2026, 11, 10) + TimeSerial(13, 45, 0), "datetime")
Print App.FormatDate(DateSerial(2026, 11, 10), "%d.%m.%Y")
