' repoinfo.bas - asks GitHub's JSON API about a repository and shows a few of its fields.
Option Explicit

Private web As Http

Private Sub Form_Load()
    Set web = CreateObject("Http")
    web.Timeout = 15000
    web.SetHeader "Accept", "application/vnd.github+json"
End Sub

Private Sub go_Click()
    Dim reply As String
    status.Caption = "Asking GitHub..."
    DoEvents
    On Error GoTo Failed
    reply = web.Get("https://api.github.com/repos/" & repo.Text)
    If web.Status <> 200 Then
        status.Caption = "GitHub says " & web.Status & " " & web.StatusText
        Exit Sub
    End If
    title.Caption = JsonText(reply, "full_name")
    desc.Caption = JsonText(reply, "description")
    stars.Caption = JsonNumber(reply, "stargazers_count") & " stars, " & _
                    JsonNumber(reply, "forks_count") & " forks"
    status.Caption = "Done"
    Exit Sub
Failed:
    status.Caption = "Error " & Err.Number & ": " & Err.Description
End Sub

' The string value of "key" in a flat JSON object ("" if it isn't there). Enough for simple
' answers; it doesn't handle every escape a JSON string may contain.
Private Function JsonText(json As String, key As String) As String
    Dim p As Long, q As Long
    p = InStr(json, """" & key & """")
    If p = 0 Then Exit Function
    p = InStr(p + Len(key) + 2, json, ":")
    p = InStr(p, json, """")
    If p = 0 Then Exit Function
    q = p + 1
    Do While q <= Len(json)
        If Mid(json, q, 1) = "\" Then
            q = q + 2
        ElseIf Mid(json, q, 1) = """" Then
            Exit Do
        Else
            q = q + 1
        End If
    Loop
    JsonText = Replace(Mid(json, p + 1, q - p - 1), "\""", """")
End Function

' The number value of "key" (0 if it isn't there).
Private Function JsonNumber(json As String, key As String) As Double
    Dim p As Long
    p = InStr(json, """" & key & """")
    If p = 0 Then Exit Function
    p = InStr(p + Len(key) + 2, json, ":")
    JsonNumber = Val(LTrim(Mid(json, p + 1, 30)))
End Function
