' Glimmerfield - the benchmark: the bot plays n frames from a seed
'
' Logic only, or (draw = True) also the full renderer onto a SoftCanvas, a
' framebuffer drawn by BASIC code. The "state:" lines are the same in every
' build; the "time:" lines are left out when quiet.
Option Explicit

Public Sub RunBench(ByVal n As Long, ByVal seed As Long, ByVal quiet As Boolean, _
                    Optional ByVal draw As Boolean = False)
    Dim f As Long, games As Long, best As Long, hud As String, hudLen As Long
    Dim t0 As Double, t1 As Double, t2 As Double, t3 As Double, t4 As Double, t5 As Double
    Dim tStart As Double, total As Double, ft As Double, worst As Double
    Dim tLogic As Double, tHash As Double, tHud As Double, tDraw As Double, tBlit As Double
    Dim sumShards As Double, sumParts As Double, maxParts As Long
    Dim h As Long, ph As Long
    Dim cv As SoftCanvas

    If draw Then
        Set cv = New SoftCanvas
        InitRender
    End If
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
        If draw Then
            DrawWorld cv
            t4 = NowMs()
            cv.Flip
            t5 = NowMs()
            tDraw = tDraw + (t4 - t3)
            tBlit = tBlit + (t5 - t4)
            If (f Mod 100) = 0 Then ph = (ph * 31 + cv.Hash()) Mod 1000003
        Else
            t5 = t3
        End If
        tLogic = tLogic + (t1 - t0)
        tHash = tHash + (t2 - t1)
        tHud = tHud + (t3 - t2)
        ft = t5 - t0
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
    If total <= 0# Then total = 0.001
    If score > best Then best = score

    If draw Then
        Print "Glimmerfield bench: " & CStr(n) & " frames, seed " & CStr(seed) & ", drawing"
    Else
        Print "Glimmerfield bench: " & CStr(n) & " frames, seed " & CStr(seed)
    End If
    Print "state: games " & CStr(games) & " best " & CStr(best) & " score " & CStr(score) & _
          " wave " & CStr(wave) & " lives " & CStr(lives) & " hash " & CStr(h)
    Print "state: shards avg " & Format$(sumShards / n, "0.00") & " particles avg " & _
          Format$(sumParts / n, "0.00") & " max " & CStr(maxParts) & " hud chars " & CStr(hudLen)
    If draw Then Print "state: picture hash " & CStr(ph)
    If Not quiet Then
        Print "time: total " & Format$(total, "0") & " ms = " & Format$(total / n, "0.000") & _
              " ms/frame (" & Format$(n * 1000# / total, "0") & " fps)"
        Print "time: logic " & Format$(tLogic / n, "0.000") & " hash " & Format$(tHash / n, "0.000") & _
              " hud " & Format$(tHud / n, "0.000") & " draw " & Format$(tDraw / n, "0.000") & _
              " blit " & Format$(tBlit / n, "0.000") & " ms/frame, worst frame " & Format$(worst, "0.0") & " ms"
    End If
End Sub
