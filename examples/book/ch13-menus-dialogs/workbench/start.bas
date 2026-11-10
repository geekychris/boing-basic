' start.bas - opens the catalog before the first form loads, so that the form's
' "$id:default" texts are translated too
Option Explicit

Sub Main()
    App.OpenCatalog "jotter.catalog"        ' translations, if a catalog is installed
    jotterWin.Show vbModal                  ' the window is named jotterWin in jotter.afg
End Sub
