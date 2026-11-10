' scan.bas - the code-behind of scan.afg: a long job in Timer slices.
' Each tick reads at most SLICE lines, updates the progress bar and checks the Cancel flag,
' then returns to the event loop, so the window can be moved, resized and clicked meanwhile.
Option Explicit

Private Const SLICE = 200            ' lines per tick

Private f As Integer                 ' the open file, 0 while no job runs
Private lines As Long, words As Long, longest As Long
Private cancelled As Boolean
Private started As Double

Private Sub startbtn_Click()
    If src.FileName = "" Then status.Caption = "Choose a file first": Exit Sub
    On Error GoTo Failed
    f = FreeFile
    Open src.FileName For Input As #f
    lines = 0: words = 0: longest = 0
    cancelled = False
    started = Timer
    progress.Value = 0
    startbtn.Enabled = False
    cancelbtn.Enabled = True
    tick.Enabled = True              ' the work starts at the next tick
    Exit Sub
Failed:
    status.Caption = "Can't open it: " & Err.Description
    f = 0
End Sub

Private Sub tick_Timer()
    Dim i As Long, text As String
    For i = 1 To SLICE
        If cancelled Or EOF(f) Then
            Finish
            Exit Sub
        End If
        Line Input #f, text
        lines = lines + 1
        words = words + CountWords(text)
        If Len(text) > longest Then longest = Len(text)
    Next
    If LOF(f) > 0 Then progress.Value = CLng(100 * (Seek(f) - 1) / LOF(f))
    status.Caption = lines & " lines so far ..."
End Sub

Private Sub cancelbtn_Click()
    cancelled = True                 ' the next tick stops (events never interrupt a tick)
End Sub

Private Sub Finish()
    tick.Enabled = False
    Close #f
    f = 0
    startbtn.Enabled = True
    cancelbtn.Enabled = False
    If cancelled Then
        status.Caption = "Cancelled after " & lines & " lines"
    Else
        progress.Value = 100
        status.Caption = lines & " lines, " & words & " words, longest line " & longest & _
                         " characters (" & Format(Timer - started, "0.0") & " s)"
    End If
End Sub

' the words of one line: runs of characters other than spaces and tabs
Private Function CountWords(ByVal text As String) As Long
    Dim i As Long, c As String, inWord As Boolean
    For i = 1 To Len(text)
        c = Mid(text, i, 1)
        If c = " " Or c = vbTab Then
            inWord = False
        ElseIf Not inWord Then
            inWord = True
            CountWords = CountWords + 1
        End If
    Next
End Function

Private Sub Form_Unload(Cancel As Integer)
    If f <> 0 Then Close #f          ' closed in the middle of a job
End Sub
