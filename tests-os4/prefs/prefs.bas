' prefs.bas - docs/ui.md group 7 on the guest: UseSetting (ENV: only) against SaveSetting
' (ENV: and ENVARC:), the locale's number and date formats, Clipboard.Unit (IFF FTXT on unit 5,
' unit 0 left alone), Clipboard.GetFormat. TAP lines and PASS/FAIL on stdout.
Dim n As Integer, fails As Integer

Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then Print "ok "; n; " - "; what Else Print "not ok "; n; " - "; what: fails = fails + 1
End Sub

' settings
SaveSetting "BoingPrefsTest", "S", "Saved", "1"
UseSetting "BoingPrefsTest", "S", "Used", "2"
Check Dir("ENV:BoingPrefsTest/S/Saved") <> "" And Dir("ENVARC:BoingPrefsTest/S/Saved") <> "", "SaveSetting writes ENV: and ENVARC:"
Check Dir("ENV:BoingPrefsTest/S/Used") <> "", "UseSetting writes ENV:"
Check Dir("ENVARC:BoingPrefsTest/S/Used") = "", "UseSetting doesn't write ENVARC:"
Check GetSetting("BoingPrefsTest", "S", "Used") = "2", "GetSetting reads a used setting"
DeleteSetting "BoingPrefsTest"
Check Dir("ENV:BoingPrefsTest", vbDirectory) = "" And Dir("ENVARC:BoingPrefsTest", vbDirectory) = "", "DeleteSetting removes both"

' locale formats
Dim dp As String, gs As String, s As String
dp = App.DecimalPoint: gs = App.GroupSeparator
Print "# decimal point """; dp; """ group separator """; gs; """"
Check Len(dp) = 1, "App.DecimalPoint"
s = App.FormatNumber(1234567.891, 2)
Print "# FormatNumber(1234567.891, 2) = "; s
Check s = "1" & gs & "234" & gs & "567" & dp & "89", "FormatNumber uses the locale's separators"
s = App.FormatDate(DateSerial(2026, 11, 10))
Print "# FormatDate(2026-11-10) = "; s
Check InStr(s, "10") > 0 And (InStr(s, "11") > 0 Or InStr(s, "Nov") > 0), "FormatDate short has the day and month"
s = App.FormatDate(DateSerial(2026, 11, 10), "%Y-%m-%d")
Print "# FormatDate(.., ""%Y-%m-%d"") = "; s
Check s = "2026-11-10", "FormatDate with a locale.library template"

' clipboard units
Dim keep As String
keep = Clipboard.GetText
Clipboard.Unit = 5
Clipboard.SetText "text on unit five"
Check Clipboard.GetText = "text on unit five", "Clipboard.Unit 5 round trip (IFF FTXT)"
Check Clipboard.GetFormat(vbCFText), "GetFormat(vbCFText) on unit 5"
Check Not Clipboard.GetFormat(vbCFBitmap), "no picture on unit 5"
Clipboard.Unit = 0
Check Clipboard.GetText = keep, "unit 0 is untouched"
Print IIf(fails = 0, "PASS", "FAIL")
