' lists.bas
Option Explicit

Private nextFile As Long

Private Sub Form_Load()
    ' rows of a list with columns: the cells separated by tabs
    files.AddItem "readme" & vbTab & "1024" & vbTab & "text"
    files.AddItem "boing.iff" & vbTab & "52311" & vbTab & "picture"
    files.AddItem "song.mod" & vbTab & "88412" & vbTab & "music"
    files.ItemData(0) = 100                 ' a number kept with the row
    files.Sort 0                            ' by name, ascending

    tree.AddNode "sys", "", "SYS:"
    tree.AddNode "c", "sys", "C"
    tree.AddNode "libs", "sys", "Libs"
    tree.AddNode "work", "", "Work:"
    tree.AddNode "games", "work", "Games"
    tree.AddNode "tank", "games", "TankDuel"
    tree.Expand "sys"

    Dim r As Long
    sheet.Redraw = False                    ' many changes: draw once at the end
    For r = 1 To 10
        sheet.TextMatrix(r, 1) = "Item " & r
        sheet.TextMatrix(r, 2) = CStr(r * 10)
    Next
    sheet.TextMatrix(0, 3) = "Total"        ' row 0 holds the column titles
    sheet.ColWidth(1) = 90
    sheet.CellBold(1, 1) = True
    sheet.CellForeColor(2, 2) = RGB(200, 0, 0)
    sheet.Redraw = True
End Sub

' --- the list ---------------------------------------------------------------------------

Private Sub files_Click()
    If files.ListIndex >= 0 Then
        fileInfo.Caption = files.Cell(files.ListIndex, 0) & ", " & files.Cell(files.ListIndex, 1) & " bytes"
    End If
End Sub

Private Sub files_DblClick()
    MsgBox "Open " & files.Cell(files.ListIndex, 0)
End Sub

Private Sub files_ColumnClick(Column As Integer)
    fileInfo.Caption = "Sorted by " & files.ColumnTitle(Column)
End Sub

Private Sub addFile_Click()
    nextFile = nextFile + 1
    files.AddItem "new" & nextFile & vbTab & "0" & vbTab & "empty"
End Sub

Private Sub removeFiles_Click()
    Dim i As Long
    For i = files.ListCount - 1 To 0 Step -1     ' from the end: the rows below move up
        If files.Selected(i) Then files.RemoveItem i
    Next
    fileInfo.Caption = files.ListCount & " files"
End Sub

' --- the tree ---------------------------------------------------------------------------

Private Sub tree_NodeClick()
    Dim k As String
    k = tree.SelectedKey
    nodeInfo.Caption = tree.NodeText(k) & " (parent: " & tree.NodeParent(k) & ")"
End Sub

Private Sub tree_Expand()
    nodeInfo.Caption = "Opened " & tree.NodeText(tree.EventKey)
End Sub

Private Sub expandAll_Click()
    tree.Expand "sys"
    tree.Expand "work"
    tree.Expand "games"
End Sub

' --- the grid ---------------------------------------------------------------------------

Private Sub sheet_EnterCell()
    cellInfo.Caption = "Row" & Str(sheet.Row) & ", column" & Str(sheet.Col) & ": " & sheet.Text
End Sub

Private Sub sheet_BeforeEdit(Row As Long, Col As Long, Cancel As Integer)
    If Col = 3 Then Cancel = True           ' the totals are computed, not typed
End Sub

Private Sub sheet_AfterEdit(Row As Long, Col As Long)
    sheet.TextMatrix(Row, 3) = CStr(Val(sheet.TextMatrix(Row, 2)) * 2)
End Sub
