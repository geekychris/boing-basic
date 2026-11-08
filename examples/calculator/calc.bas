' calc.bas - the code-behind of calc.afg: a four-function calculator.
Option Explicit

Private acc As Double        ' the value before the operator
Private op As String         ' "+", "-", "*", "/" or "" (none yet)
Private fresh As Boolean     ' the next digit starts a new number

Private Sub Form_Load()
    display.Text = "0"
    fresh = True
End Sub

Private Sub Digit(d As String)
    If fresh Or display.Text = "0" Then
        If d = "." Then display.Text = "0." Else display.Text = d
        fresh = False
    ElseIf d <> "." Or InStr(display.Text, ".") = 0 Then
        display.Text = display.Text & d
    End If
End Sub

Private Sub Operator(o As String)
    If op <> "" And Not fresh Then Equals
    acc = Val(display.Text)
    op = o
    fresh = True
    status.Caption = Str(acc) & " " & op
End Sub

Private Sub Equals()
    Dim x As Double
    x = Val(display.Text)
    On Error GoTo Failed
    Select Case op
        Case "+": acc = acc + x
        Case "-": acc = acc - x
        Case "*": acc = acc * x
        Case "/": acc = acc / x
        Case Else: acc = x
    End Select
    display.Text = CStr(acc)
    status.Caption = " "
    op = ""
    fresh = True
    Exit Sub
Failed:
    display.Text = "0"
    status.Caption = Err.Description
    op = ""
    fresh = True
End Sub

Private Sub b0_Click(): Digit "0": End Sub
Private Sub b1_Click(): Digit "1": End Sub
Private Sub b2_Click(): Digit "2": End Sub
Private Sub b3_Click(): Digit "3": End Sub
Private Sub b4_Click(): Digit "4": End Sub
Private Sub b5_Click(): Digit "5": End Sub
Private Sub b6_Click(): Digit "6": End Sub
Private Sub b7_Click(): Digit "7": End Sub
Private Sub b8_Click(): Digit "8": End Sub
Private Sub b9_Click(): Digit "9": End Sub
Private Sub bdot_Click(): Digit ".": End Sub
Private Sub badd_Click(): Operator "+": End Sub
Private Sub bsub_Click(): Operator "-": End Sub
Private Sub bmul_Click(): Operator "*": End Sub
Private Sub bdiv_Click(): Operator "/": End Sub
Private Sub beq_Click(): Equals: End Sub

Private Sub bclear_Click()
    display.Text = "0"
    acc = 0
    op = ""
    fresh = True
    status.Caption = " "
End Sub

Private Sub bback_Click()
    If Len(display.Text) > 1 Then display.Text = Left(display.Text, Len(display.Text) - 1) Else display.Text = "0"
End Sub

' Typing works too: digits, + - * / . and Return
Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim c As String
    c = Chr(KeyAscii)
    Select Case c
        Case "0" To "9", ".": Digit c
        Case "+", "-", "*", "/": Operator c
        Case "=", vbCr: Equals
    End Select
End Sub
