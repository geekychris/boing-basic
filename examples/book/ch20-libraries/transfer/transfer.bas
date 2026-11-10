' transfer.bas - two UPDATEs that happen together or not at all
Option Explicit
Dim db As SQLite

Sub Transfer(ByVal amount As Long, ByVal fromId As Long, ByVal toId As Long)
    On Error GoTo Failed
    db.BeginTransaction
    db.Execute "UPDATE account SET balance = balance + ? WHERE id = ?", amount, toId
    db.Execute "UPDATE account SET balance = balance - ? WHERE id = ?", amount, fromId
    db.Commit
    Print "moved"; amount
    Exit Sub
Failed:
    If db.InTransaction Then db.Rollback
    Print "the transfer of"; amount; "failed: "; Err.Description
End Sub

Sub Balances()
    Dim row As Variant
    For Each row In db.Query("SELECT name, balance FROM account ORDER BY id")
        Print "  "; row(0); row(1)
    Next
End Sub

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE account (id INTEGER PRIMARY KEY, name TEXT, balance INTEGER CHECK (balance >= 0));" & _
           "INSERT INTO account (name, balance) VALUES ('Ann', 100), ('Bob', 20)"
Transfer 30, 1, 2
Transfer 500, 2, 1
Balances
