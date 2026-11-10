Dim f As Integer, done As Boolean, born As Date, note As Variant, title As String

f = FreeFile
Open "record.txt" For Output As #f
Write #f, "Ada", True, #12/10/1815#, Null
Close #f

Open "record.txt" For Input As #f
Print Input(LOF(f), #f);
Close #f

Open "record.txt" For Input As #f
Input #f, title, done, born, note
Close #f
Print title; " "; done; " "; born; " "; IsNull(note)
Print TypeName(done); " "; TypeName(born); " "; TypeName(note)
Kill "record.txt"
