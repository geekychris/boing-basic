' readargs.bas - App.ReadArgs on the guest (docs/ui.md): run by tests-os4/readargs/run.sh with
' different command lines; prints what ReadArgs made of them, compared with expected.txt.
Dim ok As Variant, t As String, i As Integer
ok = App.ReadArgs("FILE/A,SIZE/N,QUIET/S,VERBOSE/T,NUMS/N/M")
Print "ReadArgs "; ok; " "; TypeName(ok)
If ok Then
    Print "FILE="; App.ArgValue("FILE"); " SIZE="; App.ArgValue("SIZE"); " QUIET="; App.ArgValue("QUIET"); _
        " VERBOSE="; App.ArgValue("VERBOSE"); " NUMS="; Replace(App.ArgValue("NUMS"), vbLf, ",")
End If
' a template with more than 32 items: error 5, not a stack overflow
For i = 1 To 33
    t = t & IIf(i > 1, ",", "") & "K" & i
Next
On Error Resume Next
ok = App.ReadArgs(t)
Print "33 items: error"; Err.Number
