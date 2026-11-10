' main.bas - uses the Counter class
Option Explicit

Sub Main()
    Dim c As Counter            ' a variable that can hold a Counter (Nothing for now)
    Print c Is Nothing
    Set c = New Counter         ' create the object
    c.Increment
    c.Increment 5
    c.Value = c.Value + 10
    c.Caption = "clicks"
    Print c.Value; c.Limit
    Print c.Describe()

    Dim d As Counter
    Set d = c                   ' a second reference to the same object
    d.Increment
    Print c.Value; d Is c

    On Error Resume Next
    c.Value = 500
    Print "Error"; Err.Number; ": "; Err.Description
    On Error GoTo 0

    Set c = Nothing             ' d still holds the object
    Print "c released"
    Set d = Nothing             ' the last reference: Class_Terminate runs
    Print "done"
End Sub
