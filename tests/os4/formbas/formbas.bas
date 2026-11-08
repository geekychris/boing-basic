' formbas.bas - code-behind of formbas.afg. Prints TAP lines; at step 2 it asks the test
' script to click the OK button (CLICK x y, screen coordinates), and checks ok_Click ran.
Option Explicit

Private n As Integer, fails As Integer, steps As Integer, clicks As Integer, loads As Integer

Private Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then
        Print "ok "; n; " - "; what
    Else
        Print "not ok "; n; " - "; what
        fails = fails + 1
    End If
End Sub

Private Sub Form_Load()
    loads = loads + 1
    Check name.Text = "Amiga", "name.Text from the .afg"
    Check list.ListCount = 2, "list.ListCount = 2"
    list.AddItem "Two"
    Check list.ListCount = 3 And list.List(2) = "Two", "list.AddItem"
    Check pick.ListIndex = 2 And pick.Text = "Blue", "pick.ListIndex/Text"
    Check speed.Value = 3, "speed.Value = 3"
    Check TypeName(ok) = "CommandButton", "TypeName(ok) = CommandButton"
End Sub

Private Sub Form_Activate()
    If steps = 0 Then Me.Caption = "Boing BASIC form test - running"
End Sub

Private Sub tick_Timer()
    steps = steps + 1
    Select Case steps
    Case 1
        name.Text = "Boing"
        Check name.Text = "Boing", "name.Text = ""Boing"""
        fast.Value = vbChecked
        Check fast.Value = 1, "fast.Value = vbChecked"
        status.Caption = "Running"
        Check status.Caption = "Running", "status.Caption"
        Check Me.Visible, "Me.Visible"
        Check formbas.ok.Caption = "_OK", "formbas.ok.Caption (form.control)"
    Case 2
        Print "CLICK"; Me.Left + ok.Left + ok.Width \ 2; Me.Top + ok.Top + ok.Height \ 2
    Case 12
        Check False, "ok_Click within 4 seconds"
        Finish
    End Select
End Sub

Private Sub ok_Click()
    clicks = clicks + 1
    Check clicks = 1, "a click on OK called ok_Click"
    Finish
End Sub

Private Sub Finish()
    tick.Enabled = False
    Unload Me
End Sub

Private Sub Form_Unload(Cancel As Integer)
    Check loads = 1, "Form_Load ran once"
    If fails = 0 Then Print "PASS ("; n; "/"; n; ")" Else Print "FAIL ("; n - fails; "/"; n; ")"
End Sub
