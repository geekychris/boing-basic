Dim WithEvents s As Src
' handler parameters differ in type from the event's: values are copied back
Sub s_Ask(answer As Integer, text As String)
    Print "handler got"; answer; " "; text
    answer = 42
    text = "changed"
End Sub
Set s = New Src
s.Go
