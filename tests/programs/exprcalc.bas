' A recursive-descent expression evaluator written in BASIC
Option Explicit
Private src As String, pos As Long

Function Peek() As String
    Do While pos <= Len(src)
        If Mid$(src, pos, 1) <> " " Then Exit Do
        pos = pos + 1
    Loop
    If pos > Len(src) Then Peek = "" Else Peek = Mid$(src, pos, 1)
End Function

Function ParseNumber() As Double
    Dim start As Long
    start = pos
    Do While pos <= Len(src)
        If InStr("0123456789.", Mid$(src, pos, 1)) = 0 Then Exit Do
        pos = pos + 1
    Loop
    If pos = start Then Err.Raise 1001, "calc", "number expected at " & pos
    ParseNumber = Val(Mid$(src, start, pos - start))
End Function

Function ParseFactor() As Double
    Dim c As String
    c = Peek()
    If c = "(" Then
        pos = pos + 1
        ParseFactor = ParseExpr()
        If Peek() <> ")" Then Err.Raise 1002, "calc", "missing )"
        pos = pos + 1
    ElseIf c = "-" Then
        pos = pos + 1
        ParseFactor = -ParseFactor()
    Else
        ParseFactor = ParseNumber()
    End If
End Function

Function ParsePower() As Double
    Dim b As Double
    b = ParseFactor()
    If Peek() = "^" Then
        pos = pos + 1
        b = b ^ ParsePower()
    End If
    ParsePower = b
End Function

Function ParseTerm() As Double
    Dim v As Double, op As String
    v = ParsePower()
    Do
        op = Peek()
        If op <> "*" And op <> "/" Then Exit Do
        pos = pos + 1
        If op = "*" Then v = v * ParsePower() Else v = v / ParsePower()
    Loop
    ParseTerm = v
End Function

Function ParseExpr() As Double
    Dim v As Double, op As String
    v = ParseTerm()
    Do
        op = Peek()
        Select Case op
            Case "+": pos = pos + 1: v = v + ParseTerm()
            Case "-": pos = pos + 1: v = v - ParseTerm()
            Case Else: Exit Do
        End Select
    Loop
    ParseExpr = v
End Function

Function Evaluate(ByVal text As String) As String
    On Error GoTo bad
    src = text
    pos = 1
    Evaluate = CStr(ParseExpr())
    If pos <= Len(src) Then Evaluate = "error: unexpected '" & Mid$(src, pos, 1) & "'"
    Exit Function
bad:
    Evaluate = "error " & Err.Number & ": " & Err.Description
End Function

Dim tests As Variant, t As Variant
tests = Array("1 + 2 * 3", "(1 + 2) * 3", "2 ^ 3 ^ 2", "-4 + 10 / 4", "7 / 0", "(1 + 2", "3 $ 4", "1.5 * (2 - -2)", "")
For Each t In tests
    Print "["; t; "] = "; Evaluate(t)
Next
