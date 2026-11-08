' viewer.bas - the code-behind of viewer.afg: list a folder, show a file as text or hex.
Option Explicit

Private current As String

Private Sub Form_Load()
    view.Locked = True
    ListFolder
End Sub

Private Sub ListFolder()
    Dim f As String, n As Long, dir_ As String
    dir_ = folder.Text
    If dir_ = "" Then Exit Sub
    If Right(dir_, 1) <> ":" And Right(dir_, 1) <> "/" Then dir_ = dir_ & "/"
    files.Clear
    f = Dir(dir_ & "*")
    Do While f <> ""
        files.AddItem f
        n = n + 1
        f = Dir()
    Loop
    status.Caption = n & " files in " & folder.Text
End Sub

Private Sub refresh_Click()
    ListFolder
End Sub

Private Sub folder_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then ListFolder
End Sub

Private Sub files_Click()
    Dim dir_ As String
    If files.ListIndex < 0 Then Exit Sub
    dir_ = folder.Text
    If Right(dir_, 1) <> ":" And Right(dir_, 1) <> "/" Then dir_ = dir_ & "/"
    ShowFile dir_ & files.Text
End Sub

Private Sub pick_Change()
    ShowFile pick.FileName
End Sub

Private Sub hex_Click()
    If current <> "" Then ShowFile current
End Sub

Private Sub ShowFile(path As String)
    Dim fn As Integer, s As String, all As String, b As Byte, i As Long, line_ As String
    On Error GoTo Failed
    current = path
    fn = FreeFile
    If hex.Value = vbChecked Then
        Open path For Binary As #fn
        For i = 0 To LOF(fn) - 1
            If i >= 4096 Then Exit For
            Get #fn, , b
            line_ = line_ & Right("0" & Hex(b), 2) & " "
            If i Mod 16 = 15 Then all = all & Right("0000" & Hex(i - 15), 4) & ": " & line_ & vbLf: line_ = ""
        Next i
        If line_ <> "" Then all = all & line_ & vbLf
    Else
        Open path For Input As #fn
        Do While Not EOF(fn)
            Line Input #fn, s
            all = all & s & vbLf
            If Len(all) > 65536 Then Exit Do
        Loop
    End If
    Close #fn
    view.Text = all
    status.Caption = path & " (" & FileLen(path) & " bytes)"
    Exit Sub
Failed:
    status.Caption = "Can't read " & path & ": " & Err.Description
End Sub

Private Sub Form_Resize()
    ' the layout resizes the gadgets; just say how big we are
    Me.Caption = "File Viewer - " & Me.Width & "x" & Me.Height
End Sub
