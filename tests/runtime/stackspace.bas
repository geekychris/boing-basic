' Runaway recursion raises error 28 (Out of stack space) in the VM and native code
Function Down(ByVal n As Long) As Long
    Down = Down(n + 1) + 1
End Function
Dim depth As Long
Sub Deep(ByVal n As Long)
    If n > depth Then depth = n
    Deep n + 1
    depth = depth - 1
End Sub
On Error Resume Next
Print Down(1)
Print "err"; Err.Number; Err.Description
Err.Clear
Deep 1
Print "err"; Err.Number; depth > 1000
Err.Clear
On Error GoTo 0
' still works afterwards
Function Fact(ByVal n As Long) As Double
    If n <= 1 Then Fact = 1 Else Fact = n * Fact(n - 1)
End Function
Print Fact(20)
' numeric literals with the Double suffix are not dates; vbKey constants
Print 1000000# / 200000#; 3# * 2#; 1# - 1#
Print vbKeyA; vbKeyZ; vbKey0; vbKey9; vbKeyF1; vbKeyF10; vbKeyNumpad5; vbKeyHome
