' sqlerrors.bas - SQLite's own errors (31601) and the others
Option Explicit
Dim db As SQLite, rs As SqlRecordset, v As Variant

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE player (name TEXT UNIQUE)"
db.Execute "INSERT INTO player VALUES (?)", "Ann"
On Error Resume Next
db.Execute "INSERT INTO player VALUES (?)", "Ann"
Print Err.Number; Err.Description; " (code"; db.ErrorCode; ")"
Err.Clear
db.Execute "SELEKT * FROM player"
Print Err.Number; Err.Description
Err.Clear
v = db.QueryValue("SELECT * FROM nowhere")
Print Err.Number; Err.Description
Err.Clear
db.Execute "INSERT INTO player VALUES (?)", "Bob", "Cy"
Print Err.Number; Err.Description
Err.Clear
Set rs = db.Query("SELECT name FROM player")
v = rs("age")
Print Err.Number; Err.Description
Err.Clear
v = rs(3)
Print Err.Number; Err.Description
Err.Clear
rs.MoveNext
rs.MoveNext
Print Err.Number; Err.Description
Err.Clear
rs.Close
db.Execute "INSERT INTO player VALUES (?)", db
Print Err.Number; Err.Description
Err.Clear
db.Timeout = -1
Print Err.Number; Err.Description
Err.Clear
db.Close
v = db.QueryValue("SELECT 1")
Print Err.Number; Err.Description
Err.Clear
db.Open "no-such-drawer/x.db"
Print Err.Number; Err.Description
