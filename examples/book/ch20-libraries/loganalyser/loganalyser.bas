' loganalyser.bas - a summary of a log file, with regular expressions
Option Explicit

Dim lineRe As RegExp, hostRe As RegExp
Dim levels(1 To 4) As String, counts(1 To 4) As Long
Dim modules As String, hosts As String, first As String, last As String
Dim f As Integer, text As String, total As Long, skipped As Long

' a list in a String: "|Http|Disk|"; add a name once
Sub AddOnce(list As String, ByVal name As String)
    If list = "" Then list = "|"
    If InStr(list, "|" & name & "|") = 0 Then list = list & name & "|"
End Sub

Function ListText(ByVal list As String) As String
    If list = "" Then ListText = "(none)" Else ListText = Replace(Mid(list, 2, Len(list) - 2), "|", ", ")
End Function

Sub Tally(ByVal level As String)
    Dim i As Long
    For i = 1 To 4
        If levels(i) = UCase(level) Then counts(i) = counts(i) + 1: Exit Sub
    Next
End Sub

Sub Main()
    Dim m As Variant, i As Long
    levels(1) = "DEBUG": levels(2) = "INFO": levels(3) = "WARN": levels(4) = "ERROR"

    Set lineRe = CreateObject("RegExp")
    lineRe.Pattern = "^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d) \[(\w+)\] (DEBUG|INFO|WARN|ERROR): (.*)$"
    lineRe.IgnoreCase = True                ' "error:" and "Error:" too
    Set hostRe = CreateObject("RegExp")
    hostRe.Pattern = "timeout .*\(([\w.-]+)\)"

    f = FreeFile
    Open "app.log" For Input As #f
    Do Until EOF(f)
        Line Input #f, text
        If lineRe.Test(text) Then
            Set m = lineRe.Execute(text)(0)
            total = total + 1
            If first = "" Then first = m.SubMatches(0) & " " & m.SubMatches(1)
            last = m.SubMatches(0) & " " & m.SubMatches(1)
            Tally m.SubMatches(3)
            If UCase(m.SubMatches(3)) = "ERROR" Then
                AddOnce modules, m.SubMatches(2)
                If hostRe.Test(m.SubMatches(4)) Then AddOnce hosts, hostRe.Execute(m.SubMatches(4))(0).SubMatches(0)
            End If
        ElseIf Trim(text) <> "" Then
            skipped = skipped + 1           ' a line in another format (a stack dump...)
        End If
    Loop
    Close #f

    Print total & " log lines from " & first & " to " & last & ", " & skipped & " other lines"
    For i = 1 To 4
        Print "  " & levels(i) & ": " & counts(i)
    Next
    Print "errors from: "; ListText(modules)
    Print "timeouts at: "; ListText(hosts)
End Sub
