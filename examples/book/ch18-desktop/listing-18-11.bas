' Ask a running Jotter for its text
Option Explicit
Dim text As String

On Error GoTo noJotter
text = App.SendARexx("JOTTER", "GETTEXT")
Print "Jotter has"; Len(text); "characters (RC"; App.ARexxRC; ")"
End
noJotter:
Print "Jotter is not running"
