Option Explicit
Dim out As Csv, table As Csv, i As Long
Set out = CreateObject("Csv")
out.Create "scores.csv"
out.WriteRecord "Player", "Score", "Comment"
out.WriteRecord "Ann", 1200, "first place"
out.WriteRecord "Bob", 950, "lost a life on" & vbLf & "level 3"
out.Close
out.Create "scores.csv", True           ' append
out.WriteRecord "Cy", 700, ""
out.Close

Set table = CreateObject("Csv")
table.HasHeader = True
table.Open "scores.csv"
Do While table.ReadRecord()
    Print table("Player"); CLng(table("Score")) * 2; " "; Replace(table("Comment"), vbLf, "\n")
Loop
table.Close
Kill "scores.csv"
