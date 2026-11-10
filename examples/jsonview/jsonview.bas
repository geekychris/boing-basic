' jsonview.bas - the code-behind of jsonview.afg: Http + JsonParse, the document as path = value lines.
Option Explicit

Private web As Http
Private doc As Variant

Private Sub Form_Load()
    Set web = CreateObject("Http")
    web.SetHeader "Accept", "application/json"
    If Command() <> "" Then url.Text = Command(): Fetch
End Sub

Private Sub go_Click()
    Fetch
End Sub

Private Sub url_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then Fetch
End Sub

Private Sub Fetch()
    Dim body As String
    On Error GoTo Failed
    status.Caption = "Fetching ..."
    DoEvents
    body = web.Get(url.Text)
    If web.Status <> 200 Then
        status.Caption = "HTTP " & web.Status & " " & web.StatusText
        Exit Sub
    End If
    doc = JsonParse(body)
    tree.Clear
    Walk "", doc
    status.Caption = tree.ListCount & " values from " & web.Url
    Exit Sub
Failed:
    status.Caption = "Error " & Err.Number & ": " & Err.Description
End Sub

' every scalar of the document as one line "path = value"
Private Sub Walk(path As String, v As Variant)
    Dim k As Variant, i As Long
    If IsObject(v) Then
        For Each k In v
            Walk path & "." & k, v(k)
        Next
    ElseIf IsArray(v) Then
        For i = 0 To UBound(v)
            Walk path & "[" & i & "]", v(i)
        Next
    ElseIf IsNull(v) Then
        tree.AddItem Mid(path, 2) & " = null"
    ElseIf VarType(v) = vbString Then
        tree.AddItem Mid(path, 2) & " = """ & v & """"
    Else
        tree.AddItem Mid(path, 2) & " = " & v
    End If
End Sub

Private Sub pretty_Click()
    If IsEmpty(doc) Then Exit Sub
    MsgBox Left(JsonStringify(doc, 2), 2000), vbInformation, "JSON"
End Sub
