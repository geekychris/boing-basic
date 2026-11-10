' Process: run commands, output, exit codes, input, environment (host shell or AmigaDOS)
Option Explicit
Dim p As Process, amiga As Boolean, rc As Long, env, i As Long, found As Boolean, lines

Set p = CreateObject("Process")
amiga = p.GetEnv("Workbench") <> ""
rc = p.Run("echo hello world")
Print "echo:"; rc; " ["; Replace(p.Output, vbLf, "\n"); "] "; p.ExitCode; " "; p.CommandLine
If amiga Then rc = p.Run("Search NIL: nothing QUIET") Else rc = p.Run("exit 5")
Print "exit code:"; rc = 5; p.ExitCode = rc
If amiga Then
    rc = p.Run("echo one" & vbLf & "echo two" & vbLf & "echo three")
Else
    rc = p.Run("printf 'one\ntwo\r\nthree'")
End If
lines = p.OutputLines()
Print "lines:"; UBound(lines) + 1; Join(lines, "|")
' input: a command that reads its standard input (Echo ? reads its arguments through ReadArgs;
' Type * would read the console, not the input)
If amiga Then rc = p.Run("Echo ?", "line A" & vbLf) Else rc = p.Run("cat", "line A" & vbLf)
Print "input:"; rc; InStr(p.Output, "line A") > 0
If amiga Then
    rc = p.Run("Type nonexistent-file-xyz")
    Print "error:"; rc > 0; Len(p.Output & p.ErrorOutput) > 0
Else
    rc = p.Run("echo oops 1>&2; exit 2")
    Print "error:"; rc > 0; Len(p.Output & p.ErrorOutput) > 0
End If
' environment
p.SetEnv "BBTEST_VAR", "forty two"
Print "getenv:"; p.GetEnv("BBTEST_VAR"); " environ:"; Environ("BBTEST_VAR")
env = p.Environment()
For i = 0 To UBound(env)
    If env(i) = "BBTEST_VAR=forty two" Then found = True
Next
Print "listed:"; found; UBound(env) > 0
rc = p.Run("echo $BBTEST_VAR")
Print "child sees:"; Trim(Replace(p.Output, vbLf, ""))
p.SetEnv "BBTEST_VAR"
Print "removed:["; p.GetEnv("BBTEST_VAR"); "]"
' a big output
If amiga Then rc = p.Run("List SYS:C LFORMAT ""%P%N""") Else rc = p.Run("i=0; while [ $i -lt 3000 ]; do echo line $i; i=$((i+1)); done")
Print "big:"; Len(p.Output) > 1000; rc
