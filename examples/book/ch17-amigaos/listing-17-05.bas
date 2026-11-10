Declare Function FilePart Lib "dos.library" (ByVal path As String) As String

Print FilePart("Work:Games/Tank/tank.bbp")
