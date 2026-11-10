Option Explicit
Dim table As Csv, h As Variant, total As Double
Set table = CreateObject("Csv")
table.HasHeader = True
table.LoadText "Item,Price,Note" & vbCrLf & _
               "Disk box,4.50,""holds 50""" & vbCrLf & _
               "Mouse mat,3.25,""blue," & vbLf & "with Boing ball""" & vbCrLf & _
               vbCrLf & _
               "Joystick,19.99"
For Each h In table.Headers
    Print "["; h; "]";
Next
Print "  price is column"; table.ColumnIndex("PRICE")
Do While table.ReadRecord()
    Print table.RecordNumber; table.LineNumber; table.FieldCount; " "; table(0); ": "; _
          Replace(table.Field("Note"), vbLf, " / ")
    total = total + Val(table.Field("Price"))
Loop
Print "total"; total; " at end: "; table.AtEnd
