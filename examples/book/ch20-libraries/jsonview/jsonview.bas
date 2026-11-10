' jsonview.bas - the code-behind of jsonview.afg: Http + JsonParse, the document shown as
' "path = value" lines, e.g.  address.geo.lat = "-37.3159"
Option Explicit

Private web As Http
Private doc As Variant                  ' the parsed document: a Dictionary, an array or a value

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
    doc = JsonParse(body)               ' error 31201 if it isn't JSON
    tree.Clear
    Walk "", doc
    status.Caption = tree.ListCount & " values from " & web.Url
    Exit Sub
Failed:
    If Err.Number = 31201 Then
        status.Caption = "The answer isn't JSON: " & Err.Description
    Else
        status.Caption = "Error " & Err.Number & ": " & Err.Description
    End If
End Sub

' every scalar of the document as one line "path = value"
Private Sub Walk(path As String, v As Variant)
    Dim k As Variant, i As Long
    If IsObject(v) Then                 ' a JSON object: a Dictionary
        For Each k In v
            Walk path & "." & k, v(k)
        Next
    ElseIf IsArray(v) Then              ' a JSON array: 0 To UBound
        For i = 0 To UBound(v)
            Walk path & "[" & i & "]", v(i)
        Next
    ElseIf IsNull(v) Then
        tree.AddItem Mid(path, 2) & " = null"
    ElseIf VarType(v) = vbString Then   ' JSON text is UTF-8: decode it for the Amiga's screen
        tree.AddItem Mid(path, 2) & " = """ & Utf8Decode(v) & """"
    Else                                ' Long, Double or Boolean
        tree.AddItem Mid(path, 2) & " = " & v
    End If
End Sub

Private Sub pretty_Click()
    If IsEmpty(doc) Then Exit Sub
    MsgBox Left(Utf8Decode(JsonStringify(doc, 2)), 2000), vbInformation, "JSON"
End Sub
