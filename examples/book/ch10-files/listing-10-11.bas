Dim f As Integer
f = FreeFile
Open "report.txt" For Output As #f
Print #f, "Monthly report"
Close #f

Print "size"; FileLen("report.txt")
FileCopy "report.txt", "backup.txt"
Name "report.txt" As "final.txt"
Print Dir("report.txt") = ""; " "; Dir("final.txt"); " "; Dir("backup.txt")

MkDir "archive"
Name "backup.txt" As "archive/backup.txt"
Print Dir("archive/*.txt")

Kill "final.txt"
Kill "archive/backup.txt"
RmDir "archive"
