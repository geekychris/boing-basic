' albums.bas - a table, three rows, a query (Extension=sqlite in albums.bbp)
Option Explicit

Sub Main()
    Dim db As SQLite, rs As SqlRecordset

    Set db = CreateObject("SQLite")
    db.Open ":memory:"
    db.Execute "CREATE TABLE album (id INTEGER PRIMARY KEY, artist TEXT, title TEXT, year INTEGER)"
    db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Kraftwerk", "Computer World", 1981
    db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Jean-Michel Jarre", "Oxygene", 1976
    db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Daft Punk", "Discovery", 2001
    Set rs = db.Query("SELECT artist, title, year FROM album WHERE year < ? ORDER BY year", 1990)
    Do Until rs.AtEnd
        Print rs("year"); rs("artist"); " - "; rs("title")
        rs.MoveNext
    Loop
    rs.Close
    Print db.QueryValue("SELECT COUNT(*) FROM album"); "albums"
    db.Close
End Sub
