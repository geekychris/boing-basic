' Tincture - saved settings (GetSetting / SaveSetting: ENV:Tincture/..., ENVARC: too)
Option Explicit

Public prefLastDir As String

Private Function GetPref(ByVal key As String, ByVal def As String) As String
    GetPref = WbGetSetting(key, def)
End Function

Private Sub PutPref(ByVal key As String, ByVal v As String)
    WbSaveSetting key, v
End Sub

Public Sub LoadPrefs()
    Dim i As Long, s As String, w() As String
    brushSize = CLng(Val(GetPref("BrushSize", "1")))
    If brushSize < 1 Or brushSize > 64 Then brushSize = 1
    brushSquare = GetPref("BrushSquare", "0") = "1"
    airRadius = CLng(Val(GetPref("AirRadius", "12")))
    airDensity = CLng(Val(GetPref("AirDensity", "24")))
    textScale = CLng(Val(GetPref("TextScale", "2")))
    showGrid = GetPref("Grid", "0") = "1"
    magZoom = CLng(Val(GetPref("MagnifierZoom", "6")))
    ditherOnReduce = GetPref("Dither", "1") = "1"
    createIcons = GetPref("Icons", "1") = "1"
    prefLastDir = GetPref("LastDir", "")
    undoBudget = CLng(Val(GetPref("UndoMegapixels", "12"))) * 1000000
    s = GetPref("Palette", "")
    If s <> "" Then
        w = Split(s, ",")
        palCount = 0
        For i = 0 To UBound(w)
            If i < 256 And IsNumeric(w(i)) Then pal(i) = CLng(w(i)): palCount = i + 1
        Next
    End If
    If palCount = 0 Then DefaultPalette
    fgColor = CLng(Val(GetPref("Foreground", CStr(vbBlack))))
    bgColor = CLng(Val(GetPref("Background", CStr(vbWhite))))
End Sub

Public Sub SavePrefs()
    Dim i As Long, s As String
    PutPref "BrushSize", CStr(brushSize)
    PutPref "BrushSquare", IIf(brushSquare, "1", "0")
    PutPref "AirRadius", CStr(airRadius)
    PutPref "AirDensity", CStr(airDensity)
    PutPref "TextScale", CStr(textScale)
    PutPref "Grid", IIf(showGrid, "1", "0")
    PutPref "MagnifierZoom", CStr(magZoom)
    PutPref "Dither", IIf(ditherOnReduce, "1", "0")
    PutPref "Icons", IIf(createIcons, "1", "0")
    PutPref "LastDir", prefLastDir
    PutPref "UndoMegapixels", CStr(undoBudget \ 1000000)
    If docMode = MODE_TRUE Then
        For i = 0 To palCount - 1
            If i > 0 Then s = s & ","
            s = s & pal(i)
        Next
        PutPref "Palette", s
    End If
    PutPref "Foreground", CStr(fgColor)
    PutPref "Background", CStr(bgColor)
End Sub

' where the autosave goes: next to the program (survives a crash of the program and of the machine)
Public Function AutosaveFile() As String
    Dim p As String
    p = App.Path
    If p = "" Then p = "T:"
    If Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    AutosaveFile = p & "Tincture.autosave.tinc"
End Function
