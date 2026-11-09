' Tincture - the Workbench side, through this one module: ARexx port, AppWindow drops,
' AppIcon, the clipboard, help, icons and settings (docs/ui.md sections 6 and 7).
' Every call is guarded: on the host (headless test runs) these are stubs or missing.
Option Explicit

Private clipCv As Object          ' helper canvas for Clipboard.GetPicture (it fills a back buffer)

Public Sub WbInit(ByVal portName As String)
    On Error Resume Next
    App.ARexxPort = portName
End Sub

Public Sub WbCleanup()
    On Error Resume Next
    App.HideAppIcon
End Sub

Public Function WbARexxName() As String
    On Error Resume Next
    WbARexxName = App.ARexxPortName
    If WbARexxName = "" Then WbARexxName = "(none)"
End Function

Public Sub WbSetRC(ByVal rc As Long)
    On Error Resume Next
    App.ARexxRC = rc
End Sub

Public Function WbDropFile(ByVal i As Long) As String
    On Error Resume Next
    WbDropFile = App.DropFile(i)
End Function

' an AppIcon while the window is iconified (pictures dropped on it open)
Public Sub WbShowAppIcon(ByVal show As Boolean)
    On Error Resume Next
    If show Then App.ShowAppIcon "Tincture", App.Path & "/Tincture" Else App.HideAppIcon
End Sub

' the image goes to the clipboard as IFF ILBM (the canvas's current target is what is copied)
Public Sub WbClipboardPut(cv As Object, ByVal img As Long)
    On Error Resume Next
    cv.SetTarget img
    Clipboard.SetPicture cv
    cv.SetTarget 0
End Sub

' a picture on the clipboard as a new image of cv (0 if there is none)
Public Function WbClipboardGet(cv As Object) As Long
    Dim tmp As String
    On Error GoTo none
    If Not Clipboard.HasPicture Then Exit Function
    If clipCv Is Nothing Then Set clipCv = CreateObject("Boing.Canvas")
    Clipboard.GetPicture clipCv
    tmp = "T:tincture-clip.ppm"
    clipCv.SaveImage tmp
    WbClipboardGet = cv.LoadImage(tmp)
    Kill tmp
    Exit Function
none:
    WbClipboardGet = 0
End Function

Public Function WbHelp(ByVal guide As String, ByVal node As String) As Boolean
    On Error GoTo noHelp
    App.ShowHelp App.Path & "/" & guide, node
    WbHelp = True
    Exit Function
noHelp:
    WbHelp = False
End Function

' a project icon for a saved picture: Icons/picture.info beside the program, default tool Tincture
Public Sub WbSaveIcon(ByVal path As String)
    On Error Resume Next
    If FileExists(path & ".info") Then Exit Sub           ' keep the user's own icon
    App.SaveIcon path, App.Path & "/Tincture", App.Path & "/Icons/picture"
End Sub

Public Function WbGetSetting(ByVal key As String, ByVal def As String) As String
    On Error GoTo fallback
    WbGetSetting = GetSetting("Tincture", "Prefs", key, def)
    Exit Function
fallback:
    WbGetSetting = def
End Function

Public Sub WbSaveSetting(ByVal key As String, ByVal v As String)
    On Error Resume Next
    SaveSetting "Tincture", "Prefs", key, v
End Sub

' the tooltype AUTOSAVE=seconds (0 = off) of the program's icon, else the default
Public Function WbToolTypeNum(ByVal name As String, ByVal def As Long) As Long
    Dim s As String
    On Error GoTo fallback
    s = App.ToolType(name, CStr(def))
    If IsNumeric(s) Then WbToolTypeNum = CLng(s) Else WbToolTypeNum = def
    Exit Function
fallback:
    WbToolTypeNum = def
End Function

' files given on the command line or as Workbench project icons
Public Function WbArgCount() As Long
    On Error Resume Next
    WbArgCount = App.ArgCount
End Function

Public Function WbArg(ByVal i As Long) As String
    On Error Resume Next
    WbArg = App.Arg(i)
End Function

Public Function WbFromWorkbench() As Boolean
    On Error Resume Next
    WbFromWorkbench = App.FromWorkbench
End Function
