' records.bas - a database file: the rows are still there when it is opened again
Option Explicit
Dim db As SQLite

Set db = CreateObject("SQLite")
db.Open "records.db"
db.Execute "CREATE TABLE IF NOT EXISTS album (id INTEGER PRIMARY KEY, artist TEXT, title TEXT, year INTEGER)"
db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Kraftwerk", "Computer World", 1981
Print "open:"; db.IsOpen; " file: "; db.Path
db.Close
Print "open:"; db.IsOpen

' the next run of a program, or another program
db.Open "records.db", True              ' True: read-only
Print db.QueryValue("SELECT COUNT(*) FROM album"); "album: "; db.QueryValue("SELECT title FROM album")
db.Close
Kill "records.db"                       ' only for this example: a real program keeps its file
