' importer.bas - the code-behind of importer.afg: a CSV file into an SQLite table.
' The import runs in Timer slices: each tick reads and inserts at most 200 records, then
' updates the fuel gauge and returns, so the window stays responsive and Cancel works.
' All the rows go in one transaction (fast; Cancel or an error rolls everything back).
'     csvimport                         choose the files in the window
'     csvimport data.csv data.db        import straight away and quit (also without a display)
Option Explicit

Const SLICE = 200

Private table As Csv
Private db As SQLite
Private ins As SqlStatement
Private total As Long, cancelled As Boolean, auto As Boolean, t0 As Double

Private Sub Form_Load()
    Dim a
    a = Split(Trim(Command()), " ")
    If UBound(a) = 1 Then           ' csvimport data.csv data.db
        src.FileName = a(0)
        dst.FileName = a(1)
        auto = True
        StartImport
    End If
End Sub

Private Sub importbtn_Click()
    StartImport
End Sub

Private Sub cancelbtn_Click()
    cancelled = True                ' the next tick stops
End Sub

' a name that is safe as an SQL identifier: letters, digits, _
Private Function Ident(ByVal s As String) As String
    Dim i As Long, c As String, r As String
    For i = 1 To Len(s)
        c = Mid(s, i, 1)
        If c Like "[A-Za-z0-9_]" Then r = r & c Else r = r & "_"
    Next
    If r = "" Or IsNumeric(Left(r, 1)) Then r = "c" & r
    Ident = r
End Function

' the number of lines of the file, for the fuel gauge (an estimate when fields hold line breaks)
Private Function CountLines(ByVal path As String) As Long
    Dim f As Integer, text As String
    f = FreeFile
    Open path For Binary As #f
    text = Space(LOF(f))
    Get #f, 1, text
    Close #f
    CountLines = UBound(Split(text, vbLf)) + 1
End Function

Private Sub StartImport()
    Dim cols, i As Long, sql As String, marks As String
    On Error GoTo Failed
    Set table = CreateObject("Csv")
    table.HasHeader = True
    table.Open src.FileName
    cols = table.Headers
    If UBound(cols) < 0 Then Err.Raise 5, , "the CSV file has no header line"
    Set db = CreateObject("SQLite")
    db.Open dst.FileName
    sql = "CREATE TABLE IF NOT EXISTS " & Ident(tbl.Text) & " ("
    For i = 0 To UBound(cols)
        sql = sql & IIf(i > 0, ", ", "") & Ident(cols(i)) & " TEXT"
        marks = marks & IIf(i > 0, ", ", "") & "?"
    Next
    db.Execute sql & ")"
    Set ins = db.Prepare("INSERT INTO " & Ident(tbl.Text) & " VALUES (" & marks & ")")
    total = CountLines(src.FileName) - 1
    progress.Min = 0
    progress.Max = IIf(total > 0, total, 1)
    progress.Value = 0
    db.BeginTransaction
    cancelled = False
    t0 = Timer
    importbtn.Enabled = False
    cancelbtn.Enabled = True
    status.Caption = "Importing " & total & " records ..."
    tick.Enabled = True
    Exit Sub
Failed:
    Finish "Can't import: " & Err.Description
End Sub

Private Sub tick_Timer()
    Dim i As Long, f, n As Long, k As Long
    On Error GoTo Failed
    For i = 1 To SLICE
        If cancelled Then
            db.Rollback
            Finish "Cancelled: nothing was imported"
            Exit Sub
        End If
        If Not table.ReadRecord() Then
            db.Commit
            Finish "Imported " & table.RecordNumber & " records into " & Ident(tbl.Text), _
                   " in " & Format(Timer - t0, "0.0") & " s"
            Exit Sub
        End If
        f = table.Fields
        n = ins.ParameterCount
        If UBound(f) + 1 <> n Then ReDim Preserve f(n - 1)      ' short or long records fit the table
        ins.Execute f
    Next
    progress.Value = IIf(table.RecordNumber > progress.Max, progress.Max, table.RecordNumber)
    status.Caption = "Importing ... " & table.RecordNumber & " of " & total
    Exit Sub
Failed:
    If db.InTransaction Then db.Rollback
    Finish "Error at record " & table.RecordNumber & ": " & Err.Description
End Sub

Private Sub Finish(ByVal message As String, Optional ByVal detail As String = "")
    tick.Enabled = False
    importbtn.Enabled = True
    cancelbtn.Enabled = False
    status.Caption = message & detail
    If Not table Is Nothing Then table.Close
    If Not db Is Nothing Then
        If db.IsOpen Then db.Close
    End If
    If auto Then
        Print message
        Unload Me
    End If
End Sub
