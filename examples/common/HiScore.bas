' HiScore - a high-score table of 8, saved as a text file (from Glimmerfield's).
' HsSetup sets the defaults' names and step before HsLoad.
Option Explicit

Public Const HS_COUNT As Long = 8

Public hsName(0 To 7) As String
Public hsScore(0 To 7) As Long
Private hsDefNames As Variant
Private hsDefStep As Long

' the table a fresh game starts with: names (8), and scores step * 8 .. step
Public Sub HsSetup(names As Variant, ByVal stp As Long)
    hsDefNames = names
    hsDefStep = stp
End Sub

Public Sub HsDefaults()
    Dim i As Long
    If IsEmpty(hsDefNames) Then
        hsDefNames = Array("NOVA", "QUILL", "EMBER", "SABLE", "TIDE", "MOTH", "FERN", "DUSK")
        hsDefStep = 1000
    End If
    For i = 0 To HS_COUNT - 1
        hsName(i) = hsDefNames(i)
        hsScore(i) = (HS_COUNT - i) * hsDefStep
    Next i
End Sub

' the score file beside the program
Public Function HsPath(ByVal fileName As String) As String
    Dim p As String
    p = App.Path
    If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    HsPath = p & fileName
End Function

Public Sub HsLoad(ByVal path As String)
    Dim f As Integer, i As Long, nm As String, sc As Long
    HsDefaults
    On Error GoTo bad
    f = FreeFile
    Open path For Input As #f
    i = 0
    Do While Not EOF(f) And i < HS_COUNT
        Input #f, nm, sc
        hsName(i) = Left$(nm, 8)
        hsScore(i) = sc
        i = i + 1
    Loop
    Close #f
    Exit Sub
bad:
    Resume cleanup
cleanup:
    On Error Resume Next
    Close #f
End Sub

Public Function HsSave(ByVal path As String) As Boolean
    Dim f As Integer, i As Long
    On Error GoTo bad
    f = FreeFile
    Open path For Output As #f
    For i = 0 To HS_COUNT - 1
        Write #f, hsName(i), hsScore(i)
    Next i
    Close #f
    HsSave = True
    Exit Function
bad:
    HsSave = False
End Function

' the place (0-based) a score would take, or -1
Public Function HsRank(ByVal sc As Long) As Long
    Dim i As Long
    For i = 0 To HS_COUNT - 1
        If sc > hsScore(i) Then
            HsRank = i
            Exit Function
        End If
    Next i
    HsRank = -1
End Function

Public Function HsInsert(ByVal nm As String, ByVal sc As Long) As Long
    Dim i As Long, r As Long
    r = HsRank(sc)
    If r >= 0 Then
        For i = HS_COUNT - 1 To r + 1 Step -1
            hsName(i) = hsName(i - 1)
            hsScore(i) = hsScore(i - 1)
        Next i
        hsName(r) = UCase$(Left$(nm, 8))
        hsScore(r) = sc
    End If
    HsInsert = r
End Function

Public Function HsLine(ByVal i As Long) As String
    HsLine = Right$(" " & CStr(i + 1), 2) & ".  " & Left$(hsName(i) & "........", 8) & _
             "  " & Format$(hsScore(i), "0000000")
End Function
