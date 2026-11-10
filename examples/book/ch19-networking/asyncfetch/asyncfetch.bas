' asyncfetch.bas - the code-behind of asyncfetch.afg: an Http download that runs in the
' background (GetAsync), with progress, a Cancel button and a form that keeps working.
Option Explicit

Private web As Http
Private started As Single

Private Sub Form_Load()
    Set web = CreateObject("Http")
    web.Timeout = 20000
    web.OnProgress = "Fetching"           ' Sub Fetching(got As Long, total As Long)
    web.OnDone = "Fetched"                ' Sub Fetched()
End Sub

' closing the window during a download: stop it first
Private Sub Form_Unload(Cancel As Integer)
    web.OnDone = ""
    web.OnProgress = ""
    If web.Busy Then
        web.Cancel
        web.Wait 5000
    End If
End Sub

Private Sub download_Click()
    meter.Value = 0
    meter.Text = ""
    status.Caption = "Connecting to " & url.Text & " ..."
    started = Timer
    web.GetAsync url.Text                 ' returns at once
    download.Enabled = False
    abort.Enabled = True
End Sub

Private Sub abort_Click()
    web.Cancel                            ' Fetched is called soon, with ErrorNumber 18
    status.Caption = "Cancelling ..."
End Sub

' called (on the program's own task) each time more of the answer has arrived
Sub Fetching(got As Long, total As Long)
    If total > 0 Then
        meter.Max = 100
        meter.Value = got * 100# / total
        meter.Text = ""
        status.Caption = Format(got / 1024, "0") & " of " & Format(total / 1024, "0") & " KB"
    Else                                  ' the server didn't say how big it is
        meter.Text = Format(got / 1024, "0") & " KB"
        status.Caption = Format(got / 1024, "0") & " KB so far"
    End If
End Sub

' called once when the request has ended, however it ended
Sub Fetched()
    Dim f As Integer, data As String
    download.Enabled = True
    abort.Enabled = False
    If web.ErrorNumber = 18 Then
        status.Caption = "Cancelled"
        meter.Value = 0
        Exit Sub
    ElseIf web.ErrorNumber <> 0 Then
        status.Caption = "Error " & web.ErrorNumber & ": " & web.ErrorText
        meter.Value = 0
        Exit Sub
    ElseIf web.Status <> 200 Then
        status.Caption = "The server said " & web.Status & " " & web.StatusText
        Exit Sub
    End If
    data = web.ResponseText
    On Error GoTo CantSave
    f = FreeFile
    Open target.Text For Binary Access Write As #f
    Put #f, , data
    Close #f
    meter.Value = meter.Max
    meter.Text = ""
    status.Caption = "Saved " & Len(data) & " bytes in " & target.Text & " (" & _
                     Format(Timer - started, "0.0") & " s)"
    Exit Sub
CantSave:
    status.Caption = "Can't save " & target.Text & ": " & Err.Description
End Sub
