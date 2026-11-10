' contacts.bas - an address book: a list of contacts kept in an SQLite database
Option Explicit

Private db As SQLite
Private currentId As Long               ' the contact being edited; 0 for a new one

Private Sub Form_Load()
    Set db = CreateObject("SQLite")
    db.Open App.Path & "/AddressBook.db"     ' the database beside the program
    db.Execute "CREATE TABLE IF NOT EXISTS contact (" & _
               "id INTEGER PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT, notes TEXT)"
    If db.QueryValue("SELECT COUNT(*) FROM contact") = 0 Then AddSamples
    LoadList 0
End Sub

Private Sub Form_Unload(Cancel As Integer)
    db.Close
End Sub

' two contacts the first time, in one transaction
Private Sub AddSamples()
    Dim ins As SqlStatement
    Set ins = db.Prepare("INSERT INTO contact (name, phone, email, notes) VALUES (?, ?, ?, ?)")
    db.BeginTransaction
    ins.Execute "Ann Example", "0123 456789", "ann@example.com", "Amiga club"
    ins.Execute "Bob O'Brien", "0987 654321", "bob@example.com", Null
    db.Commit
    ins.Close
End Sub

' fill the list from the table, sorted by name; select the row of contact selectId
Private Sub LoadList(ByVal selectId As Long)
    Dim rs As SqlRecordset, n As Long
    people.Clear
    Set rs = db.Query("SELECT id, name, IFNULL(phone, '') FROM contact ORDER BY name COLLATE NOCASE")
    Do Until rs.AtEnd
        people.AddItem rs(1) & vbTab & rs(2)
        people.ItemData(people.ListCount - 1) = rs(0)
        If rs(0) = selectId Then n = people.ListCount - 1
        rs.MoveNext
    Loop
    rs.Close
    If people.ListCount > 0 Then people.ListIndex = n Else ShowContact 0
End Sub

' show one contact in the fields (0: empty fields for a new one)
Private Sub ShowContact(ByVal id As Long)
    Dim rs As SqlRecordset
    currentId = 0
    nameField.Text = ""
    phoneField.Text = ""
    emailField.Text = ""
    notesField.Text = ""
    If id <> 0 Then
        Set rs = db.Query("SELECT name, IFNULL(phone, ''), IFNULL(email, ''), IFNULL(notes, '') " & _
                          "FROM contact WHERE id = ?", id)
        If Not rs.AtEnd Then
            currentId = id
            nameField.Text = rs(0)
            phoneField.Text = rs(1)
            emailField.Text = rs(2)
            notesField.Text = rs(3)
        End If
        rs.Close
    End If
    deleteButton.Enabled = currentId <> 0
    status.Caption = db.QueryValue("SELECT COUNT(*) FROM contact") & " contacts"
End Sub

Private Sub people_Click()
    If people.ListIndex >= 0 Then ShowContact people.ItemData(people.ListIndex)
End Sub

Private Sub addButton_Click()
    people.ListIndex = -1
    ShowContact 0
    status.Caption = "New contact: type the details and press Save"
End Sub

Private Sub saveButton_Click()
    If Trim(nameField.Text) = "" Then
        status.Caption = "A contact needs a name"
        Exit Sub
    End If
    If currentId = 0 Then
        db.Execute "INSERT INTO contact (name, phone, email, notes) VALUES (?, ?, ?, ?)", _
                   Trim(nameField.Text), phoneField.Text, emailField.Text, notesField.Text
        currentId = db.LastInsertId
        status.Caption = "Added " & Trim(nameField.Text)
    Else
        db.Execute "UPDATE contact SET name = ?, phone = ?, email = ?, notes = ? WHERE id = ?", _
                   Trim(nameField.Text), phoneField.Text, emailField.Text, notesField.Text, currentId
        status.Caption = "Saved " & Trim(nameField.Text)
    End If
    LoadList currentId
End Sub

Private Sub deleteButton_Click()
    If currentId = 0 Then Exit Sub
    If MsgBox("Delete " & nameField.Text & "?", vbYesNo + vbQuestion, "Address Book") <> vbYes Then Exit Sub
    db.Execute "DELETE FROM contact WHERE id = ?", currentId
    LoadList 0
End Sub
