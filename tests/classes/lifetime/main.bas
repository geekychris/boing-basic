Function MakeNode(ByVal n As String) As Node
    Dim x As New Node
    x.Name = n
    Set MakeNode = x
End Function

Sub Scope()
    Dim a As Node
    Set a = MakeNode("local")
    Print "in scope "; a.Name
End Sub

Sub Main()
    Scope
    Print "after scope"
    Dim head As Node
    Set head = MakeNode("one")
    Set head.NextNode = MakeNode("two")
    Set head.NextNode.NextNode = MakeNode("three")
    Dim p As Node
    Set p = head
    Do Until p Is Nothing
        Print p.Name;
        Set p = p.NextNode
    Loop
    Print
    Set head = Nothing
    Print "list released"
    Dim o As Object
    Set o = MakeNode("late")
    Print o.Upper; " "; TypeName(o)
    On Error Resume Next
    Dim r As Long
    r = o.Fail
    Print Err.Number; Err.Description
    Err.Clear
    o.Missing
    Print Err.Number
    On Error GoTo 0
    With MakeNode("with")
        Print .Upper
    End With
    Print "end"
End Sub
