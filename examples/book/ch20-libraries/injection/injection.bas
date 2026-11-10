' injection.bas - a value full of quotes and SQL is stored as it is
Option Explicit
Dim db As SQLite, nasty As String

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE contact (id INTEGER PRIMARY KEY, name TEXT)"
nasty = "O'Brien'); DELETE FROM contact; --"
db.Execute "INSERT INTO contact (name) VALUES (?)", "Ann"
db.Execute "INSERT INTO contact (name) VALUES (?)", nasty
db.Execute "INSERT INTO contact (name) VALUES (?)", Array("Bob")
Print db.QueryValue("SELECT COUNT(*) FROM contact"); "contacts"
Print db.QueryValue("SELECT name FROM contact WHERE id = ?", 2)
Print db.QueryValue("SELECT id FROM contact WHERE name LIKE ?", "b%")
