' scores.bas - a recordset loop, For Each, QueryAll and QueryValue
Option Explicit
Dim db As SQLite, rs As SqlRecordset, row As Variant, a As Variant, i As Long

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE score (player TEXT, points INTEGER, level INTEGER);" & _
           "INSERT INTO score VALUES ('Ann', 5200, 7), ('Bob', 4100, 5), ('Cy', 900, 2), ('Ann', 3000, 4)"

Set rs = db.Query("SELECT player, SUM(points) AS total FROM score GROUP BY player ORDER BY total DESC")
Print rs.FieldCount; "columns: "; rs.FieldName(0); ", "; rs.FieldName(1)
Do Until rs.AtEnd
    Print rs.RowNumber; ". "; rs("player"); rs("total")
    rs.MoveNext
Loop
rs.Close

For Each row In db.Query("SELECT player, level FROM score WHERE level > ?", 4)
    Print row(0); " reached level"; row(1)
Next

a = db.QueryAll("SELECT player, points FROM score ORDER BY points")
For i = 0 To UBound(a, 1)
    Print a(i, 0); "="; a(i, 1); " ";
Next
Print
Print "best: "; db.QueryValue("SELECT MAX(points) FROM score")
Print "nobody: "; IsEmpty(db.QueryValue("SELECT player FROM score WHERE points > 99999"))
