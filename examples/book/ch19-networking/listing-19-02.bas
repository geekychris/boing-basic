Dim web As Http
Set web = CreateObject("Http")
If web.TlsAvailable() Then
    Print "HTTPS works here"
Else
    Print "No AmiSSL: http:// addresses only"
End If
