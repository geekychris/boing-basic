' Startup.bas - Jotter starts here (Startup=Sub Main)
Option Explicit

' the version string: the Version command finds it in the native program
Public Const VERSTAG = "$VER: Jotter 1.0 (09.11.2026)"
Public Const APPNAME = "Jotter"

Public Sub Main()
    App.OpenCatalog "jotter.catalog"      ' before the form loads, so its texts are translated
    editor.Show vbModal                   ' returns when the window is closed
End Sub
