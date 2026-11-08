' Glimmerfield - console benchmark of the game logic
'
'   boing run Bench.bbp --bench 3000 [--seed 1987] [--draw] [--quiet]
'
' --draw also runs the renderer onto a SoftCanvas (a framebuffer in BASIC).
'
' The bot plays N frames from a fixed seed (a new game, seed + games, after
' each game over). The "state" lines are identical in every build; with
' --quiet only those are printed (that is what the test compares).
Option Explicit

Sub Main()
    Dim args() As String, i As Long, n As Long, seed As Long, quiet As Boolean, draw As Boolean

    n = 2000
    seed = 1987
    args = Split(Trim$(Command$), " ")
    i = 0
    Do While i <= UBound(args)
        Select Case LCase$(args(i))
            Case "--bench"
                If i < UBound(args) Then
                    i = i + 1
                    n = CLng(args(i))
                End If
            Case "--seed"
                If i < UBound(args) Then
                    i = i + 1
                    seed = CLng(args(i))
                End If
            Case "--quiet"
                quiet = True
            Case "--draw"
                draw = True
            Case Else
                If IsNumeric(args(i)) Then n = CLng(args(i))
        End Select
        i = i + 1
    Loop

    RunBench n, seed, quiet, draw
End Sub
