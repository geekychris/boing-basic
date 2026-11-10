' Settings from the program's icon, with defaults for a Shell start
Option Explicit
Dim size As Long, pubScreen As String

size = Val(App.ToolType("FONTSIZE", "13"))
pubScreen = App.ToolType("PUBSCREEN", "Workbench")
Print "Font size"; size
Print "Screen: "; pubScreen
If App.FromWorkbench Then
    Print "Started from Workbench"
Else
    Print "Started from the Shell, arguments: """; Command; """"
End If
