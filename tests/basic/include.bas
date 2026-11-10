' #Include: a file beside the program and a generated binding (bindings/exec.bi), each added
' once as a module of its own (its Public declarations are visible here)
#Include "include_lib.bi"
#Include "exec.bi"
#include "include_lib.bi"
Sub Main()
    Print Twice(21); LIB_K; MEMF_CHIP; MEMF_FAST
End Sub
