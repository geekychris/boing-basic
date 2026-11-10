Dim f As Integer, name As String, age As Integer, height As Double

f = FreeFile
Open "people.csv" For Output As #f
Write #f, "Ada Lovelace", 36, 1.65
Write #f, "Grace Hopper", 85, 1.68
Close #f

Open "people.csv" For Input As #f
Print Input(LOF(f), #f);           ' the whole file, as it is
Close #f

Open "people.csv" For Input As #f
Do Until EOF(f)
    Input #f, name, age, height
    Print name; " is"; age; "and"; height; "m tall"
Loop
Close #f

Kill "people.csv"
