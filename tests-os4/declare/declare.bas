' declare.bas - OS4 library calls from BASIC: generated bindings (Alias "#slot") and
' hand-written Declares (slot looked up by name). Prints TAP lines and PASS/FAIL.
Option Explicit

Declare Function MyStricmp Lib "utility.library" Alias "Stricmp" (ByVal a As String, ByVal b As String) As Long
Declare Function ToUpperChar Lib "utility.library" Interface "main" Version 50 Alias "ToUpper" (ByVal c As Long) As Long

Private n As Integer, fails As Integer

Private Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then Print "ok"; n; "- "; what Else Print "not ok"; n; "- "; what: fails = fails + 1
End Sub

Sub Main()
    Dim buf As String, k As Long, fh As Long, s As String

    Check FindTask(vbNullString) <> 0, "exec FindTask(NULL) (bindings, #50)"
    Check AvailMem(MEMF_ANY) > 1000000, "exec AvailMem(MEMF_ANY) > 1 MB"
    Check MyStricmp("Boing", "BOING") = 0, "utility Stricmp by name (Alias ""Stricmp"")"
    Check ToUpperChar(Asc("q")) = Asc("Q"), "utility ToUpper with Interface/Version"

    ' dos.library through the bindings: write a file, read its size back
    fh = Dos_Open("T:bb_declare_test", MODE_NEWFILE)
    Check fh <> 0, "dos Open(MODE_NEWFILE)"
    If fh <> 0 Then
        k = FPuts(fh, "Boing!")
        Check k = 0, "dos FPuts (a String argument)"
        Dos_Close fh
    End If
    Check FileLen("T:bb_declare_test") = 6, "FileLen sees the 6 bytes"
    Kill "T:bb_declare_test"

    ' a buffer the function fills
    Shell "setenv bb_declare_var Amiga", True
    buf = Space(64)
    k = GetVar("bb_declare_var", buf, 64, 0)
    Check k = 5 And Left(buf, k) = "Amiga", "dos GetVar fills a Space(64) buffer"
    Shell "unsetenv bb_declare_var", True

    If fails = 0 Then Print "PASS ("; n; ")" Else Print "FAIL ("; n - fails; "/"; n; ")"
End Sub
