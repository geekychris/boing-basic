' sysinfo.bas - calling AmigaOS 4 libraries with Declare and the generated bindings.
'   boing run sysinfo.bas
' The Declares below are written out to show the forms. A program can instead take the whole
' API from the generated bindings (tools/genbind, from the SDK; each Declare names its
' interface slot, Alias "#n"):  #Include "exec.bi"  (or Uses=exec,dos,intuition in a .bbp).
Option Explicit

' exec.library, interface "main" (the default)
Declare Function FindTask Lib "exec.library" Alias "#50" (ByVal name_ As String) As Long
Declare Function AvailMem Lib "exec.library" Alias "#15" (ByVal attributes As Long) As Long
' dos.library, Interface and Version written out; no Alias: the runtime finds GetVar's slot
Declare Function GetVar Lib "dos.library" Interface "main" Version 50 _
    (ByVal name_ As String, ByVal buffer As String, ByVal size As Long, ByVal flags As Long) As Long
' intuition.library, by name (the runtime finds the slot)
Declare Sub DisplayBeep Lib "intuition.library" (ByVal screen As Long)

Const MEMF_ANY = 0
Const MEMF_LARGEST = &H20000

Dim buf As String, n As Long

Print "This task is at &H"; Hex(FindTask(vbNullString))   ' vbNullString = NULL
Print "Free memory:   "; AvailMem(MEMF_ANY) \ 1024; "KB"
Print "Largest block: "; AvailMem(MEMF_LARGEST) \ 1024; "KB"

buf = Space(256)                ' a buffer GetVar fills (ByVal String is copied back)
n = GetVar("Workbench", buf, 256, 0)
If n >= 0 Then Print "Workbench version: "; Left(buf, n)

DisplayBeep 0
Print "Beep!"
