Option Explicit
Dim c As New Collection
c.Add 10, "ten"
On Error Resume Next
c.Add 11, "TEN"
Print Err.Number; Err.Description
Err.Clear
Print c("eleven")
Print Err.Number; Err.Description
Err.Clear
Print c(2)
Print Err.Number; Err.Description
