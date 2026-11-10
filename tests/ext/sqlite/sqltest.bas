' SQLite: tables, parameters, types, recordsets, QueryValue/QueryAll, prepared statements,
' transactions, errors (docs/sqlite.md)
Option Explicit
Dim db As SQLite, rs As SqlRecordset, st As SqlStatement, n As Long, v, a, i As Long, row

Set db = CreateObject("SQLite")
Print "available:"; db.Available; " version 3:"; Left(db.Version, 2) = "3."
On Error Resume Next
Kill "sqltest.db"
On Error GoTo 0
db.Open "sqltest.db"
Print "open:"; db.IsOpen; " "; db.Path
db.Execute "CREATE TABLE player (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, score INTEGER, avg REAL, joined TEXT, pic BLOB);" & _
           "CREATE INDEX player_score ON player(score)"
n = db.Execute("INSERT INTO player (name, score, avg, joined) VALUES (?, ?, ?, ?)", "Ann", 5200, 3.75, DateSerial(2026, 11, 10))
Print "insert:"; n; db.LastInsertId; db.Changes
db.Execute "INSERT INTO player (name, score, avg) VALUES (?, ?, ?)", Array("Bob", 4100, 2.5)
db.Execute "INSERT INTO player (name, score, avg, pic) VALUES (?, ?, ?, ?)", "Cy", 900, Null, "x" & Chr(0) & "y"
db.Execute "INSERT INTO player (name, score) VALUES ('Dee', 3000000000)"
db.Execute "INSERT INTO player (name, score) VALUES (?, ?)", "O'Brien; DROP TABLE player", True
Print "rows:"; db.QueryValue("SELECT COUNT(*) FROM player")

Set rs = db.Query("SELECT id, name, score, avg, joined, pic FROM player ORDER BY id")
Print "fields:"; rs.FieldCount; " "; rs.FieldName(1); " "; rs.FieldName(5)
Do Until rs.AtEnd
    v = rs("pic")
    If IsNull(v) Then v = "null" Else v = Len(v)
    Print rs.RowNumber; " "; rs("name"); " "; rs.Field("score"); " "; TypeName(rs("score")); " "; rs(3); " "; TypeName(rs(3)); " ["; rs("joined"); "] "; v
    rs.MoveNext
Loop
Print "EOF:"; rs.EOF; rs.RowNumber
rs.Close

' parameters and For Each
For Each row In db.Query("SELECT name, score FROM player WHERE score > ? AND name <> ? ORDER BY score DESC", 1000, "Bob")
    Print row(0); "="; row(1); " ";
Next
Print
Print "value:"; db.QueryValue("SELECT name FROM player WHERE score = ?", 4100); " none:"; IsEmpty(db.QueryValue("SELECT name FROM player WHERE id = 99"))
Print "sum:"; db.QueryValue("SELECT SUM(score) FROM player WHERE score < 10000"); " expr:"; db.QueryValue("SELECT 7 * 6"); db.QueryValue("SELECT upper(?)", "boing")
a = db.QueryAll("SELECT id, name FROM player WHERE id <= 3 ORDER BY id")
Print "all:"; UBound(a, 1); UBound(a, 2); a(0, 1); a(2, 0); IsEmpty(db.QueryAll("SELECT * FROM player WHERE 0"))
Print "date:"; db.QueryValue("SELECT strftime('%Y', joined) FROM player WHERE name = 'Ann'")

' prepared statement, transaction
Set st = db.Prepare("INSERT INTO player (name, score) VALUES (?, ?)")
Print "params:"; st.ParameterCount
db.BeginTransaction
Print "in transaction:"; db.InTransaction
For i = 1 To 200
    st.Execute "bot" & i, i * 10
Next
db.Commit
Print "bots:"; db.QueryValue("SELECT COUNT(*) FROM player WHERE name LIKE 'bot%'"); db.InTransaction
db.BeginTransaction
db.Execute "DELETE FROM player WHERE name LIKE 'bot%'"
Print "deleted:"; db.Changes
db.Rollback
Print "after rollback:"; db.QueryValue("SELECT COUNT(*) FROM player WHERE name LIKE 'bot%'")
Set st = db.Prepare("SELECT name FROM player WHERE score BETWEEN ? AND ? ORDER BY score")
Set rs = st.Query(15, 35)
Do Until rs.AtEnd: Print rs(0); " ";: rs.MoveNext: Loop
rs.Close
Set rs = st.Query(1990, 2000)
Print rs(0)
rs.Close
st.Close
n = db.Execute("UPDATE player SET score = score + 1 WHERE name LIKE 'bot1%'")
Print "updated:"; n

' errors
On Error Resume Next
db.Execute "INSERT INTO player (name) VALUES ('Ann')"
Print "unique:"; Err.Number; " "; Err.Description; " code"; db.ErrorCode: Err.Clear
db.Execute "SELEKT 1"
Print "syntax:"; Err.Number; " "; Err.Description: Err.Clear
db.Execute "INSERT INTO player (name, score) VALUES (?, ?)", "only one"
Print "count:"; Err.Number: Err.Clear
Set rs = db.Query("SELECT name FROM player WHERE id = 1")
v = rs("nope")
Print "column:"; Err.Number: Err.Clear
rs.MoveNext
rs.MoveNext
Print "past end:"; Err.Number: Err.Clear
rs.Close
db.Execute "INSERT INTO player (name) VALUES (?)", Array(1, 2)
Print "array:"; Err.Number: Err.Clear
db.Close
v = db.QueryValue("SELECT 1")
Print "closed:"; Err.Number; db.IsOpen: Err.Clear
db.Open "sqltest.db", True
db.Execute "DELETE FROM player"
Print "read-only:"; Err.Number: Err.Clear
Print "still there:"; db.QueryValue("SELECT COUNT(*) FROM player")
db.Close
db.Open "no-such-dir/x.db"
Print "bad path:"; Err.Number: Err.Clear
' in memory
db.Open ":memory:"
db.Execute "CREATE TABLE t (x)"
Print "memory:"; db.Execute("INSERT INTO t VALUES (1), (2), (3)"); db.QueryValue("SELECT SUM(x) FROM t")
db.Close
Kill "sqltest.db"
