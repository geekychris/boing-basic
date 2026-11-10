' Startup.bas - asks for a screen mode, opens the game's own screen and plays on it
Option Explicit

Public Const APPNAME = "BoingCatch"

Public Sub Main()
    Dim dlg As Object
    Set dlg = CreateObject("Boing.CommonDialog")
    dlg.DialogTitle = "Boing Catch: choose a screen mode"
    dlg.ScreenModeID = CLng(GetSetting(APPNAME, "Screen", "Mode", "0"))
    dlg.ShowScreenMode
    If Not dlg.Cancelled Then
        ' the 640 x 400 picture and the layout's margin need a bit more than 640 x 400
        If dlg.ScreenWidth < 680 Or dlg.ScreenHeight < 440 Then
            MsgBox "That mode is too small: the game uses 800 x 600.", vbInformation, "Boing Catch"
        Else
            SaveSetting APPNAME, "Screen", "Mode", CStr(dlg.ScreenModeID)
            On Error GoTo noScreen
            App.OpenScreen dlg.ScreenModeID, dlg.ScreenWidth, dlg.ScreenHeight, dlg.ScreenDepth, "Boing Catch"
            On Error GoTo 0
        End If
    End If
start:
    ' loaded now, so it opens on that screen; without one, its screen=own opens 800 x 600
    play.Show vbModal
    Exit Sub
noScreen:
    MsgBox "Can't open that screen mode." & vbLf & "The game uses 800 x 600.", vbExclamation, "Boing Catch"
    Resume start
End Sub
