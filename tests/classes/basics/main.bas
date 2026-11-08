Option Explicit

Sub Main()
    Dim c As Counter
    Set c = New Counter
    c.Increment
    c.Increment 5
    c.Value = c.Value + 10
    Print c.Value; c.Twice; c.Describe
    c.Label = "first"
    Print TypeName(c); TypeOf c Is Counter; c Is Nothing
    Dim d As Counter
    Set d = c
    d.Increment
    Print c.Value; c Is d
    On Error Resume Next
    c.Value = -1
    Print "error"; Err.Number; Err.Description
    On Error GoTo 0
    Set d = Nothing
    Set c = Nothing
    Print "released"

    Dim o As Object
    Set o = New Counter
    o.Increment 3
    o.Label = "late"
    Print o.Value; o.Twice; o.Describe
    Set o = Nothing

    Dim accounts As New Collection
    Dim a As Account
    Set a = New Account
    a.Init "Ada", 100
    accounts.Add a, "ada"
    Set a = New Account
    a.Init "Bob", 50
    accounts.Add a, "bob"
    accounts("bob").Deposit 25.5
    Print accounts.Count; accounts("ada").Balance; accounts(2).Balance
    Dim item As Variant
    For Each item In accounts
        Print item.Owner; " "; item.Withdraw(70); item.Balance
    Next
    With accounts.Item("ada")
        .Deposit 1
        Print .Owner; .Balance
    End With
    accounts.Remove "ada"
    Print accounts.Count; accounts(1).Owner
End Sub
