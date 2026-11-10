Declare Function AllocVec Lib "exec.library" Alias "#13" (ByVal byteSize As Long, ByVal attributes As Long) As Long
Declare Sub FreeVec Lib "exec.library" Alias "#28" (ByVal memoryBlock As Long)
Public Const MEMF_CLEAR = 65536
Print "These lines come from exec.bi"
