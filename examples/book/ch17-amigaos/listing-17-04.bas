Option Explicit

Declare Function GetVar Lib "dos.library" Alias "#165" _
    (ByVal name_ As String, ByVal buffer As String, ByVal size As Long, ByVal flags As Long) As Long

Function NoZero(ByVal s As String) As String
    Dim p As Long
    p = InStr(s, Chr$(0))
    If p > 0 Then NoZero = Left$(s, p - 1) Else NoZero = s
End Function

Sub Main()
    Dim buf As String, n As Long
    buf = Space(256)
    n = GetVar("Language", buf, Len(buf), 0)
    If n >= 0 Then Print "Language: "; NoZero(buf) Else Print "Language is not set"
End Sub
