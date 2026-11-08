Dim a As New Thing
Sub Touch(t As Thing)
    Print "touch"; t.Id
End Sub
Sub Local1()
    Dim x As New Thing
    Print "local dim done"
    Print "local id"; x.Id
End Sub
Print "start"
Print "a.Id"; a.Id
Print "again"; a.Id
Set a = Nothing
Print "after nothing"
Print "Is Nothing:"; a Is Nothing
Set a = Nothing
Touch a
Local1
Dim h As New Holder
Print "holder made"
h.Items.Add "x"
Print "items"; h.Items.Count
Print "inner"; h.InnerId
Print "end"
