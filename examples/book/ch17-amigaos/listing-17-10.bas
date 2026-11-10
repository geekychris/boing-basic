' A utility.library hook whose function is written in BASIC
Option Explicit

Declare Function CallHookPkt Lib "utility.library" Alias "#17" _
    (ByVal hook As Long, ByVal object_ As Long, ByVal message As Long) As Long

' struct Hook: h_MinNode (8 bytes), h_Entry at 8, h_SubEntry at 12, h_Data at 16
Const HOOK_SIZE = 20
Const H_ENTRY = 8
Const H_DATA = 16

' called by the OS with the hook, the object and the message
Function Doubler(ByVal hook As Long, ByVal obj As Long, ByVal msg As Long) As Long
    Doubler = msg * 2 + PeekL(hook + H_DATA)
End Function

Sub Main()
    Dim hook As Long
    hook = AllocMem(HOOK_SIZE, True)          ' cleared memory for the structure
    PokeL hook + H_ENTRY, AddressOf Doubler
    PokeL hook + H_DATA, 1000
    Print "hook says"; CallHookPkt(hook, 0, 21)   ' 21 * 2 + 1000
    FreeMem hook
End Sub
