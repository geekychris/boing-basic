' Pointer builtins for Declare'd OS calls. On a 64-bit host real pointers do not fit a Long and
' raise error 5; on AmigaOS 4 they are addresses. Prints the same on both.
Dim x As Long, s As String, o As Object, p As Long, ok As Boolean
Print StrPtr(""); StrPtr(vbNullString); ObjPtr(o); PeekS(0) = ""
On Error Resume Next
x = 77
p = VarPtr(x)
ok = Err.Number = 5: If Err.Number = 0 Then ok = PeekL(p) = 77
Print "VarPtr"; ok: Err.Clear
p = AllocMem(64, True)
ok = Err.Number = 5
If Err.Number = 0 Then PokeL p, 12345: PokeB p + 8, 65: PokeB p + 9, 66: ok = PeekL(p) = 12345 And PeekS(p + 8) = "AB" And PeekW(p + 12) = 0: FreeMem p
Print "AllocMem"; ok: Err.Clear
p = TagList(&H80000001, 2, &H80000003, 4)
ok = Err.Number = 5
If Err.Number = 0 Then ok = PeekL(p) = &H80000001 And PeekL(p + 4) = 2 And PeekL(p + 16) = 0: FreeTagList p
Print "TagList"; ok: Err.Clear
p = TagList(1): Print "odd"; Err.Number: Err.Clear
x = PeekB(0): Print "peek0"; Err.Number
