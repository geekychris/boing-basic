' ScShell - the game shell (game.c's game_update and game_draw): the fixed 25 Hz world, the
' events to sound, the title cycle (the painting, the autopilot's demo, the rules in turn), the
' help pages, pause, and which screen to draw. Used by the form and the console bench.
Option Explicit

Public helpPage As Long, helpAuto As Boolean, paused As Boolean, titleArt As Boolean
Public quietEvents As Boolean
Private titleT0 As Double
Private Const TITLE_DEMO_MS As Double = 12000
Private Const TITLE_PAGE_MS As Double = 8000
Private Const TITLE_ART_MS As Double = 8000

Public Sub HandleEvents()
    Dim t As Long, a As Long, b As Long
    Do While WorldPopEvent(t, a, b)
        If Not quietEvents Then SoundEvent t, a
    Loop
End Sub

' the title's cycle, by the clock (game_update's title part); hasArt: the painting loaded
Public Sub TitleCycle(ByVal nowMs As Double, ByVal hasArt As Boolean)
    Dim art As Double, t As Double, cycle As Double, p As Long
    If wState = GS_TITLE Then
        If hasArt Then art = TITLE_ART_MS Else art = 0
        cycle = art + TITLE_DEMO_MS + HELP_PAGES * TITLE_PAGE_MS
        t = nowMs - titleT0
        If t < 0 Or t >= cycle Then
            titleT0 = nowMs: t = 0
        End If
        titleArt = t < art
        t = t - art
        If t < 0 Then t = 0
        If helpPage = 0 Or helpAuto Then
            If t < TITLE_DEMO_MS Then p = 0 Else p = 1 + Int((t - TITLE_DEMO_MS) / TITLE_PAGE_MS)
            If p > HELP_PAGES Then p = HELP_PAGES
            helpAuto = p > 0
            helpPage = p
        End If
    Else
        titleT0 = nowMs
        titleArt = False
        If helpAuto Then
            helpPage = 0: helpAuto = False
        End If
    End If
End Sub

' one 40 ms step of the world
Public Sub ShellTick(ByVal inp As Long)
    If paused Or (helpPage <> 0 And wState <> GS_TITLE) Then Exit Sub
    WorldUpdate inp
    HandleEvents
    If wSiren <> 0 And (wFrame Mod 13) = 0 And Not quietEvents Then Sfx SFX_SIREN
End Sub

Public Sub DrawFrame(cv As Object)
    If titleArt And wState = GS_TITLE And helpPage = 0 Then
        DrawTitleArt cv
    ElseIf helpPage <> 0 Then
        DrawHelp cv, helpPage
    ElseIf wState = GS_UPDATE Then
        DrawUpdate cv
    Else
        DrawScene cv
        DrawOverlay cv
        If wState = GS_TITLE Then DrawTitleText cv
        DrawHud cv, paused
    End If
End Sub
