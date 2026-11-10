' started from Workbench (WBRun) by tools/os4guest.py: App.EXEName / Title / Path / FromWorkbench
' must be filled in (argc is 0 then); the results go to RAM:bbtest/wbstart.out
Dim f As Integer
f = FreeFile
Open "RAM:bbtest/wbstart.out" For Output As #f
Print #f, "EXEName="; App.EXEName
Print #f, "Title="; App.Title
Print #f, "Path="; App.Path
Print #f, "FromWorkbench="; App.FromWorkbench
Print #f, "ArgCount="; App.ArgCount
Print #f, "Command="; Command$
Print #f, "StartInfo="; App.StartInfo
' (WBRun / OpenWorkbenchObject start it with a CLI and argc 1 on OS 4.1 FE, so FromWorkbench
' isn't required here; a double-click gives argc 0, which bb_sys_init handles from the WBStartup)
Print #f, IIf(App.EXEName = "wbstart" And App.Title = "wbstart" And App.Path <> "", "PASS", "FAIL")
Close #f
