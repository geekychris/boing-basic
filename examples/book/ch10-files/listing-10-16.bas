Dim rc As Long
rc = Shell("List RAM: QUICK")
If rc <> 0 Then Print "List failed with"; rc
