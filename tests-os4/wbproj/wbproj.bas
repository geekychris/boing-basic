' wbproj.bas - started by tests-os4/wbproj/run.sh as a project icon whose default tool is boing,
' with a second icon selected: the tooltypes come from this project's icon, the other icon is
' App.Arg(0), ReadArgs reads the tooltypes and checks /A. Results to RAM:bbtest/wbproj.out.
Dim f As Integer, n As Integer, fails As Integer
f = FreeFile
Open "RAM:bbtest/wbproj.out" For Output As #f

Sub Check(ok As Boolean, what As String)
    n = n + 1
    If ok Then Print #f, "ok "; n; " - "; what Else Print #f, "not ok "; n; " - "; what: fails = fails + 1
End Sub

Print #f, "# EXEName "; App.EXEName; " FromWorkbench "; App.FromWorkbench; " ArgCount "; App.ArgCount
Check App.FromWorkbench, "FromWorkbench for a project started by Workbench"
Check App.ToolType("SIZE") = "7", "App.ToolType reads the project's own icon (SIZE=7): " & App.ToolType("SIZE")
Check App.ArgCount = 1, "the other selected icon is an argument (ArgCount 1)"
If App.ArgCount > 0 Then Check LCase(Right(App.Arg(0), 13)) = "bbt/other.txt", "App.Arg(0) = " & App.Arg(0)
Check App.ReadArgs("SIZE/N/A,MODE/K"), "ReadArgs from the tooltypes"
Check App.ArgValue("SIZE") = "7" And App.ArgValue("MODE") = "fast", "ArgValue SIZE=7 MODE=fast"
Check Not App.ReadArgs("SIZE/N,MISSING/A"), "a /A key without a tooltype: ReadArgs False"
Print #f, IIf(fails = 0, "PASS", "FAIL")
Close #f
