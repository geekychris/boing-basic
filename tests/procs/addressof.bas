' AddressOf: native entry points for callbacks (called by the OS through Declare'd APIs)
Function HookFunc(ByVal hook As Long, ByVal obj As Long, ByVal msg As Long) As Long
    HookFunc = msg
End Function
Sub Other(ByVal x As Long)
End Sub
Dim p As Long, q As Long
p = AddressOf HookFunc
q = AddressOf Other
Print p <> 0; q <> 0; p = AddressOf HookFunc; p <> q
