' readings.bas - a thousand inserts in one transaction, and a rollback
Option Explicit
Dim db As SQLite, ins As SqlStatement, i As Long

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE reading (id INTEGER PRIMARY KEY, sensor TEXT, value REAL)"

Set ins = db.Prepare("INSERT INTO reading (sensor, value) VALUES (?, ?)")
Print "parameters:"; ins.ParameterCount
db.BeginTransaction
For i = 1 To 1000
    ins.Execute "temp" & (i Mod 3), i / 10
Next
db.Commit
ins.Close
Print "rows:"; db.QueryValue("SELECT COUNT(*) FROM reading"); " last id:"; db.LastInsertId

db.BeginTransaction
Print "deleted:"; db.Execute("DELETE FROM reading WHERE sensor = ?", "temp0"); db.InTransaction
db.Rollback
Print "after rollback:"; db.QueryValue("SELECT COUNT(*) FROM reading"); db.InTransaction
Print "average:"; db.QueryValue("SELECT ROUND(AVG(value), 2) FROM reading WHERE sensor = 'temp1'")
