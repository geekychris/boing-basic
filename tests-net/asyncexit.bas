' asyncexit.bas - a program that ends while asynchronous requests still run: they are cancelled
' and their workers end with it (the runners check the time it takes, and on AmigaOS 4 that no
' "Boing BASIC worker" process is left).   boing run asyncexit.bas HTTP_BASE HTTPS_BASE CA_FILE
Option Explicit
Private a As Http, b As Http, c As Http

Sub Main()
    Dim args() As String
    args = Split(Command(), " ")
    Set a = CreateObject("Http")
    Set b = CreateObject("Http")
    Set c = CreateObject("Http")
    a.GetAsync args(0) & "/slow"
    b.GetAsync args(0) & "/drip"
    c.Timeout = 60000
    c.GetAsync "http://10.255.255.1/"
    Print "ok 1 - started"
    Print "PASS ends"          ' (the runners check that nothing is left running)
End Sub
