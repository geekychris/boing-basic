' conv.bas - the code-behind of conv.afg (exercise 4 of the Boing BASIC manual).
' Type in either field and the other one follows.
Option Explicit

Private busy As Boolean      ' True while we set a field ourselves (see celsius_Change)

Private Sub Form_Load()
    ' runs once, before the window opens: give the fields their first values
    ShowCelsius 20
End Sub

' --- typing in the fields ------------------------------------------------------------------

Private Sub celsius_Change()
    ' Setting fahrenheit.Text below fires fahrenheit_Change, which would set celsius.Text,
    ' which fires celsius_Change again... busy stops that ping-pong.
    If busy Then Exit Sub
    If IsNumeric(celsius.Text) Then
        busy = True
        fahrenheit.Text = Nice(Val(celsius.Text) * 9 / 5 + 32)
        busy = False
        Describe Val(celsius.Text)
    Else
        feel.Caption = "Type a number."
    End If
End Sub

Private Sub fahrenheit_Change()
    If busy Then Exit Sub
    If IsNumeric(fahrenheit.Text) Then
        busy = True
        celsius.Text = Nice((Val(fahrenheit.Text) - 32) * 5 / 9)
        busy = False
        Describe (Val(fahrenheit.Text) - 32) * 5 / 9
    Else
        feel.Caption = "Type a number."
    End If
End Sub

' --- buttons and the check box -------------------------------------------------------------

Private Sub freezing_Click()
    ShowCelsius 0
End Sub

Private Sub boiling_Click()
    ShowCelsius 100
End Sub

Private Sub whole_Click()
    ShowCelsius Val(celsius.Text)        ' write both fields again, rounded or not
End Sub

Private Sub quit_Click()
    Unload Me                            ' the last form unloaded ends the program
End Sub

' --- helpers ----------------------------------------------------------------------------------

' Put a Celsius value in both fields.
Private Sub ShowCelsius(ByVal c As Double)
    busy = True
    celsius.Text = Nice(c)
    fahrenheit.Text = Nice(c * 9 / 5 + 32)
    busy = False
    Describe c
End Sub

' A number as text: whole degrees, or one decimal place.
Private Function Nice(ByVal x As Double) As String
    If whole.Value = vbChecked Then
        Nice = CStr(Round(x))
    Else
        Nice = Format(x, "0.0")
    End If
End Function

' Say how it feels.
Private Sub Describe(ByVal c As Double)
    Select Case c
    Case Is < 0: feel.Caption = "Freezing: wrap up warm!"
    Case Is < 12: feel.Caption = "Cold."
    Case Is < 20: feel.Caption = "Mild."
    Case Is < 28: feel.Caption = "Warm."
    Case Is < 100: feel.Caption = "Hot!"
    Case Else: feel.Caption = "Boiling!"
    End Select
End Sub
