Dim names() As String
Dim n As Long
n = 2
ReDim names(n)
names(0) = "Ann": names(1) = "Bob": names(2) = "Cy"
ReDim Preserve names(4)
Print names(0); names(2); "["; names(4); "]"; UBound(names)
ReDim names(1)
Print "["; names(0); "]"; UBound(names)
