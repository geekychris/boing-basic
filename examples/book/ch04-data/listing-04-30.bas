Dim fixed(3) As Integer, dyn() As Integer
fixed(2) = 5
ReDim dyn(10)
Erase fixed, dyn
Print fixed(2); UBound(fixed)
On Error Resume Next
Print UBound(dyn)
Print "Error"; Err.Number; Err.Description
