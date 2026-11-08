' Glimmerfield - console benchmark of the game logic
'
'   boing run Bench.bbp --bench 3000 [--seed 1987] [--quiet]
'
' The bot plays N frames from a fixed seed (a new game, seed + games, after
' each game over). The "state" lines are identical in every build; with
' --quiet only those are printed (that is what the test compares).
Option Explicit

Sub Main()
    Dim args() As String, i As Long, n As Long, seed As Long, quiet As Boolean
    Dim f As Long, games As Long, best As Long, hud As String, hudLen As Long
    Dim t0 As Double, t1 As Double, t2 As Double, t3 As Double, tStart As Double
    Dim tLogic As Double, tHash As Double, tHud As Double, ft As Double, worst As Double
    Dim total As Double, sumShards As Double, sumParts As Double, maxParts As Long
    Dim h As Long

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
            Case Else
                If IsNumeric(args(i)) Then n = CLng(args(i))
        End Select
        i = i + 1
    Loop

    botMode = True
    NewGame seed
    tStart = NowMs()
    For f = 1 To n
        t0 = NowMs()
        GameStep
        If state = ST_GAMEOVER And overTimer = 0 Then
            If score > best Then best = score
            games = games + 1
            NewGame seed + games
        End If
        t1 = NowMs()
        h = (h * 7 + StateHash()) Mod 1000003
        t2 = NowMs()
        hud = HudText()
        hudLen = hudLen + Len(hud)
        t3 = NowMs()
        tLogic = tLogic + (t1 - t0)
        tHash = tHash + (t2 - t1)
        tHud = tHud + (t3 - t2)
        ft = t3 - t0
        If ft > worst Then worst = ft
        sumShards = sumShards + shardCount
        sumParts = sumParts + partCount
        If partCount > maxParts Then maxParts = partCount
        If Not quiet And (f Mod 500) = 0 Then
            Print "frame " & CStr(f) & ": score " & CStr(score) & " wave " & CStr(wave) & _
                  " shards " & CStr(shardCount) & " particles " & CStr(partCount)
        End If
    Next f
    total = NowMs() - tStart
    If score > best Then best = score

    Print "Glimmerfield bench: " & CStr(n) & " frames, seed " & CStr(seed)
    Print "state: games " & CStr(games) & " best " & CStr(best) & " score " & CStr(score) & _
          " wave " & CStr(wave) & " lives " & CStr(lives) & " hash " & CStr(h)
    Print "state: shards avg " & Format$(sumShards / n, "0.00") & " particles avg " & _
          Format$(sumParts / n, "0.00") & " max " & CStr(maxParts) & " hud chars " & CStr(hudLen)
    If Not quiet Then
        Print "time: total " & Format$(total, "0") & " ms = " & Format$(total / n, "0.000") & _
              " ms/frame (" & Format$(n * 1000# / IIfD(total), "0") & " fps)"
        Print "time: logic " & Format$(tLogic / n, "0.000") & " hash " & Format$(tHash / n, "0.000") & _
              " hud " & Format$(tHud / n, "0.000") & " ms/frame, worst frame " & Format$(worst, "0.0") & " ms"
    End If
End Sub

' guard against a zero duration on a coarse clock
Private Function IIfD(ByVal t As Double) As Double
    If t <= 0# Then t = 0.001
    IIfD = t
End Function
