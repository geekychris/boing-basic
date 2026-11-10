' Socket name resolution errors (host only: on AmigaOS gethostbyname has no timeout, and a
' guest without a reachable DNS server can wait for minutes)
Dim a
Set a = CreateObject("Socket")
On Error Resume Next
a.Connect "no-such-host.invalid", 80
Print "resolve:"; Err.Number
