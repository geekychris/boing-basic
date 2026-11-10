' formpos.bas - the form's Left/Top/Width/Height: set in Form_Load before the window is open,
' two in a row (the second must not undo the first), and Move. TAP lines and PASS/FAIL.
Option Explicit
Dim n As Integer, fails As Integer, stage As Integer

Private Sub Check(ByVal ok As Boolean, ByVal what As String)
    n = n + 1
    If ok Then Print "ok "; n; " - "; what Else Print "not ok "; n; " - "; what: fails = fails + 1
End Sub

Private Sub Form_Load()
    Me.Left = 60
    Me.Top = 70
    Me.Width = 300
    Check Me.Left = 60 And Me.Top = 70 And Me.Width = 300, "set in Form_Load: read back before the window opens"
End Sub

Private Sub tick_Timer()
    stage = stage + 1
    Select Case stage
    Case 1
        Check Me.Left = 60 And Me.Top = 70, "the window opened where Form_Load put it (" & Me.Left & "," & Me.Top & ")"
        Check Me.Width = 300, "with the width Form_Load gave it (" & Me.Width & ")"
        Me.Left = 200
        Me.Top = 150
        Check Me.Left = 200 And Me.Top = 150, "two settings in a row read back at once"
    Case 2
        Check Me.Left = 200 And Me.Top = 150, "and the window is there: the second didn't undo the first (" & Me.Left & "," & Me.Top & ")"
        Me.Move 100, 90, 360
    Case 3
        Check Me.Left = 100 And Me.Top = 90 And Me.Width = 360, "Move x, y, width (" & Me.Left & "," & Me.Top & "," & Me.Width & ")"
        tick.Enabled = False
        If fails = 0 Then Print "PASS "; n Else Print "FAIL "; n - fails; "/"; n
        Unload Me
    End Select
End Sub
