' sqltypes.bas - each kind of value in, and what comes back out
Option Explicit
Dim db As SQLite, rs As SqlRecordset

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE t (what TEXT, v)"
db.Execute "INSERT INTO t VALUES (?, ?)", "Long", 42
db.Execute "INSERT INTO t VALUES ('big integer', 3000000000)"
db.Execute "INSERT INTO t VALUES (?, ?)", "Double", 2.5
db.Execute "INSERT INTO t VALUES (?, ?)", "Currency", CCur(19.99)
db.Execute "INSERT INTO t VALUES (?, ?)", "whole Currency", CCur(20)
db.Execute "INSERT INTO t VALUES (?, ?)", "Boolean", True
db.Execute "INSERT INTO t VALUES (?, ?)", "Date", DateSerial(2026, 11, 10) + TimeSerial(14, 30, 0)
db.Execute "INSERT INTO t VALUES (?, ?)", "bytes", "A" & Chr(0) & "B"
db.Execute "INSERT INTO t VALUES (?, ?)", "Null", Null
db.Execute "INSERT INTO t VALUES (?, ?)", "Empty", Empty
db.Execute "INSERT INTO t (what) VALUES ('no value')"

Set rs = db.Query("SELECT what, v, typeof(v) FROM t")
Do Until rs.AtEnd
    Print rs(0); ": stored as "; rs(2); ", read as "; TypeName(rs(1))
    rs.MoveNext
Loop
Print Len(db.QueryValue("SELECT v FROM t WHERE what = 'bytes'")); "bytes"
Print db.QueryValue("SELECT v FROM t WHERE what = 'Date'")
Print Year(CDate(db.QueryValue("SELECT v FROM t WHERE what = 'Date'")))
Print db.QueryValue("SELECT date(v, '+1 month') FROM t WHERE what = 'Date'")
Print "["; db.QueryValue("SELECT IFNULL(v, '') FROM t WHERE what = 'no value'"); "]"
