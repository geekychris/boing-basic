' desk.bas FILE=name SIZE=n QUIET - docs/ui.md "Notifications, Commodities, ReadArgs": ReadArgs,
' a Ringhio notification, a Commodities hotkey (ctrl alt shift f9, pressed by the test runner's
' injector) arriving as HotKey_Pressed. Results to RAM:bbtest/desk.out.
Dim f As Integer, t As Single, n As Integer, fails As Integer, pressed As String
f = FreeFile
Open "RAM:bbtest/desk.out" For Output As #f

Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then Print #f, "ok "; n; " - "; what Else Print #f, "not ok "; n; " - "; what: fails = fails + 1
End Sub

App.Title = "BoingDeskTest2"
Check App.ReadArgs("FILE/A,SIZE/N,QUIET/S,EXTRA/K"), "App.ReadArgs(""FILE/A,SIZE/N,QUIET/S,EXTRA/K"")"
Check App.ArgValue("FILE") = "abc.txt", "FILE = abc.txt (" & App.ArgValue("FILE") & ")"
Check App.ArgValue("SIZE") = "5", "SIZE/N = 5"
Check App.ArgValue("QUIET") = "1", "QUIET/S set"
Check App.ArgValue("EXTRA") = "", "EXTRA/K absent"
On Error Resume Next
App.Notify "Boing BASIC", "A notification from the desk test"
Check Err.Number = 0, "App.Notify (Ringhio) error " & Err.Number & ", result " & App.NotifyResult
Err.Clear
App.HotKey "f9", "ctrl alt shift f9"
Check Err.Number = 0, "App.HotKey ""ctrl alt shift f9"" error " & Err.Number
On Error GoTo 0
Print #f, "READY"
Close #f
f = FreeFile
Open "RAM:bbtest/desk.out" For Append As #f
t = Timer
Do While Timer - t < 8 And pressed = ""
    DoEvents
Loop
Check pressed = "f9", "the hotkey arrived as HotKey_Pressed(""f9"")"
Print #f, IIf(fails = 0, "PASS", "FAIL")
Close #f

Sub HotKey_Pressed(Name As String)
    pressed = Name
End Sub
