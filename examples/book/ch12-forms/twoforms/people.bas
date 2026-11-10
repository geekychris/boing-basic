' people.bas - the startup form
Option Explicit

Private Sub Form_Load()
    Debug.Print "people: Form_Load"
End Sub

Private Sub add_Click()
    If AskName("Add a person", "") Then names.AddItem person.Answer
End Sub

Private Sub edit_Click()
    If names.ListIndex < 0 Then MsgBox "Choose a name first", vbExclamation: Exit Sub
    If AskName("Change the name", names.Text) Then names.List(names.ListIndex) = person.Answer
End Sub

Private Sub names_DblClick()
    edit_Click
End Sub

' the dialog: set it up, show it modally, read what it left in its Public variables.
' dlgPerson is the form (the window name in person.afg), person its code-behind module.
Private Function AskName(ByVal title As String, ByVal start As String) As Boolean
    Load dlgPerson                      ' loads the form (Form_Load runs) without showing it
    dlgPerson.Caption = title
    dlgPerson.nameField.Text = start    ' a control of another form: form.control
    dlgPerson.Show vbModal              ' returns when the dialog is hidden or unloaded
    AskName = person.Accepted           ' a Public variable of the module person.bas
    Unload dlgPerson
End Function

Private Sub about_Click()
    aboutBox.Show                       ' not modal: both windows take input
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If UnloadMode = 0 Then              ' the close gadget, not Unload in code
        If MsgBox("Quit?", vbOKCancel + vbQuestion) = vbCancel Then Cancel = True
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    Unload aboutBox                     ' the program ends when the last form is unloaded
End Sub
