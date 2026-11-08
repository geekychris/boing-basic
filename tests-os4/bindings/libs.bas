' libs.bas - the generated bindings against the real libraries (see libs.bbp, libs.out).
' Uses the pointer builtins PeekB/W/L, PokeB/W/L, PeekS, StrPtr, VarPtr, TagList, AllocMem.
Option Explicit

' hand-written Declares: by name (the runtime looks up the slot), with Interface and Version
Declare Function MyFindTask Lib "exec.library" Alias "FindTask" (ByVal name_ As String) As Long
Declare Function UpperChar Lib "utility.library" Interface "main" Version 50 Alias "ToUpper" (ByVal c As Long) As Long
' error paths
Declare Function NoSuchLib Lib "nosuch_boing.library" Alias "#5" () As Long
Declare Function TooNew Lib "dos.library" Version 9999 Alias "IoErr" () As Long
Declare Function NoSuchFunc Lib "dos.library" Alias "NoSuchFunctionBoing" () As Long

Private n As Integer, fails As Integer

Private Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then Print "ok "; CStr(n); " - "; what Else Print "not ok "; CStr(n); " - "; what: fails = fails + 1
End Sub

Sub Main()
    TestExec
    TestDos
    TestUtility
    TestGraphics
    TestLocale
    TestErrors
    If fails = 0 Then Print "PASS "; CStr(n) Else Print "FAIL "; CStr(n - fails); "/"; CStr(n)
End Sub

Private Sub TestExec()
    Dim p As Long, q As Long, i As Long
    Check FindTask(vbNullString) <> 0, "exec FindTask(NULL) via exec.bi (slot #50)"
    Check MyFindTask(vbNullString) = FindTask(vbNullString), "the same through a Declare by name"
    p = AllocVecTagList(256, TagList(AVT_Type, MEMF_PRIVATE, AVT_ClearWithValue, 0))
    Check p <> 0, "exec AllocVecTagList(256, TagList(AVT_Type, MEMF_PRIVATE, AVT_ClearWithValue, 0))"
    Check PeekL(p) = 0 And PeekL(p + 252) = 0, "the block is cleared"
    PokeL p, &H12345678: PokeW p + 4, &HBEEF: PokeB p + 6, 65
    Check PeekL(p) = &H12345678 And PeekW(p + 4) = &HBEEF And PeekB(p + 6) = 65, "PokeL/W/B and PeekL/W/B round trip"
    Check PeekB(p) = &H12, "big-endian byte order"
    q = AllocVecTagList(256, TagList(AVT_Type, MEMF_PRIVATE, AVT_ClearWithValue, 0))
    CopyMem p, q, 7
    Check PeekL(q) = &H12345678 And PeekB(q + 6) = 65 And PeekB(q + 7) = 0, "exec CopyMem copies 7 bytes"
    For i = 0 To 4: PokeB q + i, Asc(Mid("Boing", i + 1, 1)): Next
    PokeB q + 5, 0
    Check PeekS(q) = "Boing", "PeekS reads a C string"
    FreeVec p
    FreeVec q
    Check AvailMem(MEMF_ANY) > 1000000, "exec AvailMem(MEMF_ANY) > 1 MB"
End Sub

Private Sub TestDos()
    Dim fh As Long, lk As Long, buf As String, k As Long, mem As Long, s As String
    fh = Dos_Open("T:boing_bind_test", MODE_NEWFILE)
    Check fh <> 0, "dos Open(T:boing_bind_test, MODE_NEWFILE)"
    s = "Hello, Amiga!"
    Check Dos_Write(fh, StrPtr(s), Len(s)) = 13, "dos Write 13 bytes from StrPtr(s)"
    Check Dos_Close(fh) <> 0, "dos Close"
    fh = Dos_Open("T:boing_bind_test", MODE_OLDFILE)
    mem = AllocMem(64, True)
    Check Dos_Read(fh, mem, 64) = 13, "dos Read gives the 13 bytes back"
    Check PeekS(mem) = "Hello, Amiga!", "and they are the same"
    Dos_Close fh
    FreeMem mem
    lk = Dos_Lock("T:boing_bind_test", SHARED_LOCK)
    Check lk <> 0, "dos Lock(SHARED_LOCK)"
    buf = Space(256)
    Check NameFromLock(lk, buf, 256) <> 0, "dos NameFromLock"
    Check LCase(Right(RTrim(Replace(buf, Chr(0), " ")), 15)) = "boing_bind_test", "the name ends in boing_bind_test"
    Dos_UnLock lk
    Check Dos_Lock("T:boing_no_such_file", SHARED_LOCK) = 0, "Lock of a missing file = 0"
    Check IoErr() = ERROR_OBJECT_NOT_FOUND, "IoErr() = ERROR_OBJECT_NOT_FOUND"
    Kill "T:boing_bind_test"
    Check SetVar("boing_bind_var", "Boing!", 6, GVF_LOCAL_ONLY) <> 0, "dos SetVar (local)"
    buf = Space(32)
    k = GetVar("boing_bind_var", buf, 32, GVF_LOCAL_ONLY)
    Check k = 6 And Left(buf, k) = "Boing!", "dos GetVar fills a Space(32) buffer"
    Check DeleteVar("boing_bind_var", GVF_LOCAL_ONLY) <> 0, "dos DeleteVar"
    Check GetVar("boing_bind_var", buf, 32, GVF_LOCAL_ONLY) = -1, "GetVar after DeleteVar = -1"
End Sub

Private Sub TestUtility()
    Dim tags As Long, ti As Long, cd As Long
    Check Stricmp("Boing", "BOING") = 0 And Stricmp("a", "b") < 0, "utility Stricmp"
    Check Strnicmp("Amiga500", "AMIGA1200", 5) = 0, "utility Strnicmp"
    Check UpperChar(Asc("q")) = Asc("Q"), "utility ToUpper (Declare with Interface/Version)"
    tags = TagList(&H80001001, 42, &H80001002, 7)
    Check GetTagData(&H80001002, -1, tags) = 7, "utility GetTagData finds a tag"
    Check GetTagData(&H80001003, -1, tags) = -1, "and returns the default for a missing one"
    ti = FindTagItem(&H80001001, tags)
    Check ti <> 0 And PeekL(ti) = &H80001001 And PeekL(ti + 4) = 42, "utility FindTagItem -> struct TagItem"
    cd = AllocMem(14, True)
    Amiga2Date 86400 * 366 + 3600 * 13 + 60 * 5 + 9, cd   ' 1979-01-02 13:05:09
    Check PeekW(cd) = 9 And PeekW(cd + 2) = 5 And PeekW(cd + 4) = 13, "utility Amiga2Date: 13:05:09"
    Check PeekW(cd + 6) = 2 And PeekW(cd + 8) = 1 And PeekW(cd + 10) = 1979, "and 2.1.1979"
    FreeMem cd
End Sub

Private Sub TestGraphics()
    Dim scr As Long, win As Long, rp As Long
    scr = LockPubScreen(vbNullString)
    Check scr <> 0, "intuition LockPubScreen(NULL)"
    Check PeekW(scr + 12) >= 640 And PeekW(scr + 14) >= 400, "the screen is at least 640x400"
    UnlockPubScreen vbNullString, scr
    win = OpenWindowTagList(0, TagList(WA_Left, 10, WA_Top, 30, WA_Width, 200, WA_Height, 100, _
                                       WA_Title, StrPtr("Boing bindings test")))
    Check win <> 0, "intuition OpenWindowTagList"
    If win <> 0 Then
        rp = PeekL(win + 50)              ' struct Window: RPort at offset 50
        Check rp <> 0, "the window's RastPort"
        SetAPen rp, 1
        RectFill rp, 20, 30, 60, 70
        Check ReadPixel(rp, 40, 50) = 1, "graphics SetAPen + RectFill, ReadPixel sees pen 1"
        SetAPen rp, 0
        RectFill rp, 20, 30, 60, 70
        Check ReadPixel(rp, 40, 50) = 0, "and pen 0 after clearing it"
        CloseWindow win
    End If
End Sub

Private Sub TestLocale()
    Dim loc As Long
    loc = OpenLocale(vbNullString)
    Check loc <> 0, "locale OpenLocale(NULL)"
    Check ConvToUpper(loc, Asc("b")) = Asc("B"), "locale ConvToUpper"
    CloseLocale loc
End Sub

Private Sub TestErrors()
    Dim e As Long
    On Error Resume Next
    e = NoSuchLib()
    Check Err.Number = 48, "a missing library: error 48"
    Err.Clear
    e = TooNew()
    Check Err.Number = 48, "dos.library Version 9999: error 48"
    Err.Clear
    e = NoSuchFunc()
    Check Err.Number = 453, "an unknown function: error 453"
    On Error GoTo 0
End Sub
