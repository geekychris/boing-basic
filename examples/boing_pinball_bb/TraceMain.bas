' Boing Pinball trace: the bot plays each table from the seeds the C original's
' tools/trace.c uses and prints the same lines (state hash every 1000 steps).
'   boing run Trace.bbp [games [steps [table]]]
Option Explicit

Sub Main()
    Dim args() As String, games As Long, steps As Long, t0 As Long, t1 As Long
    games = 2: steps = 6000: t0 = 0: t1 = TB_COUNT - 1
    args = Split(Trim$(Command$), " ")
    If UBound(args) >= 0 Then If Len(args(0)) Then games = CLng(args(0))
    If UBound(args) >= 1 Then steps = CLng(args(1))
    If UBound(args) >= 2 Then t0 = CLng(args(2)): t1 = t0
    RunTrace games, steps, t0, t1
End Sub
