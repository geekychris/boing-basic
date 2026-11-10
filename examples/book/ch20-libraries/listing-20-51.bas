Option Explicit
Dim table As Csv
Set table = CreateObject("Csv")
table.HasHeader = True
table.LoadText "name,age,city" & vbLf & _
               "Ann,34,""Bonn, Germany""" & vbLf & _
               """Bob """"B"""" Smith"",41,"
Do While table.ReadRecord()
    Print table.Field("name"); " is "; table.Field("age"); " ["; table.Field("city"); "]"
Loop
