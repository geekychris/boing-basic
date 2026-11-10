Option Explicit
Const EXPECTED = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
Dim web As Http, data As String
Set web = CreateObject("Http")
data = web.Get("https://example.com/files/game.lha")
If Sha256(data) <> EXPECTED Then
    MsgBox "The download is damaged: please try again", vbExclamation
End If
