' Runs anywhere: uses exec.library when it is there, and says so when it is not
Option Explicit

Declare Function AvailMem Lib "exec.library" Alias "#15" (ByVal attributes As Long) As Long

Const MEMF_ANY = 0

Sub Main()
    Dim free As Long
    On Error Resume Next
    free = AvailMem(MEMF_ANY)
    Select Case Err.Number
        Case 0
            Print "Free memory:"; free \ 1024; "KB"
        Case 48
            Print "No exec.library here (error 48)"
        Case Else
            Print "Error"; Err.Number
    End Select
End Sub
