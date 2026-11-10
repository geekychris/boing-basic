Option Explicit
Dim web As Socket
Set web = CreateObject("Socket")
web.Connect "example.com", 80
web.Send "HEAD / HTTP/1.0" & vbCrLf & "Host: example.com" & vbCrLf & vbCrLf
Print web.ReceiveLine()            ' HTTP/1.0 200 OK
web.Close
