' webfetch.bas - the code-behind of webfetch.afg: an Http GET into a text editor.
Option Explicit

Private web As Http

Private Sub Form_Load()
    Set web = CreateObject("Http")
    web.Timeout = 15000
    page.Locked = True
    If Not web.TlsAvailable() Then status.Caption = "HTTPS isn't available here (no AmiSSL): http:// only"
    If Command() <> "" Then              ' webfetch URL: fetch it straight away
        url.Text = Command()
        Fetch
    End If
End Sub

Private Sub go_Click()
    Fetch
End Sub

Private Sub url_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then Fetch
End Sub

Private Sub Fetch()
    Dim body As String, t As Single
    status.Caption = "Fetching " & url.Text & " ..."
    Me.Enabled = False
    DoEvents
    web.VerifyCertificate = (verify.Value = vbChecked)
    t = Timer
    On Error GoTo Failed
    body = web.Get(url.Text)
    Me.Enabled = True
    If headers.Value = vbChecked Then
        page.Text = "HTTP " & web.Status & " " & web.StatusText & vbLf & Replace(web.ResponseHeaders, vbCr, "") & vbLf & body
    Else
        page.Text = body
    End If
    status.Caption = web.Status & " " & web.StatusText & " - " & web.BytesReceived & " bytes, " & _
                     web.ContentType & ", " & Format(Timer - t, "0.00") & " s" & _
                     IIf(web.Redirects > 0, " (redirected to " & web.Url & ")", "")
    Exit Sub
Failed:
    Me.Enabled = True
    page.Text = ""
    status.Caption = "Error " & Err.Number & ": " & Err.Description
End Sub
