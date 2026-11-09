' Marble Tilt - the rules (a port of mt_core.c from amiga_mcp's examples/marble_tilt).
' Tilt a floating 12 x 12 maze board to roll a marble to the exit: holes, gates,
' bumpers, sand and checkpoints, against the clock. 16.16 fixed point exactly as
' the C (A3Fix.bas): the autopilot's whole game gives the C's state hash.
'
' Cells:  .  floor   #  wall   (space) a hole   S start   E exit   C checkpoint
'         B  bumper  G  gate (open 3 s, shut 3 s)   Z  sand
Option Explicit

Public Const MT_N As Long = 12
Public Const MT_CELL As Long = 40
Public Const MT_R As Long = 9
Public Const MT_LEVELS As Long = 8
Public Const MT_TILT_MAX As Long = 7864            ' FX(0.12) radians
Public Const MT_GATE_T As Long = 75
Public Const MT_FALL_T As Long = 25
Public Const MT_BETWEEN As Long = 60

Public Const MT_IN_LEFT As Long = 1
Public Const MT_IN_RIGHT As Long = 2
Public Const MT_IN_UP As Long = 4
Public Const MT_IN_DOWN As Long = 8

Public Const MTE_NONE As Long = 0
Public Const MTE_WALL As Long = 1
Public Const MTE_BUMP As Long = 2
Public Const MTE_FALL As Long = 3
Public Const MTE_RESPAWN As Long = 4
Public Const MTE_CHECKPOINT As Long = 5
Public Const MTE_GATE As Long = 6
Public Const MTE_EXIT As Long = 7
Public Const MTE_LEVEL As Long = 8
Public Const MTE_TIMEOUT As Long = 9
Public Const MTE_OVER As Long = 10
Public Const MTE_WIN As Long = 11
Public Const MT_MAX_EVENTS As Long = 16

' cell codes (Asc of the level characters)
Public Const CH_FLOOR As Long = 46       ' .
Public Const CH_WALL As Long = 35        ' #
Public Const CH_HOLE As Long = 32        ' space
Public Const CH_START As Long = 83       ' S
Public Const CH_EXIT As Long = 69        ' E
Public Const CH_CHECK As Long = 67       ' C
Public Const CH_BUMPER As Long = 66      ' B
Public Const CH_GATE As Long = 71        ' G
Public Const CH_SAND As Long = 90        ' Z

Private Const TILT_RATE As Long = 1572           ' MT_TILT_MAX / 5
Private Const VMAX As Long = 327680              ' FX(5)
Private Const BUMP_KICK As Long = 163840         ' FX(2.5)
Private Const BUMPER_R As Long = 13

Public Type MtEvent
    etype As Long
    a As Long
    b As Long
End Type

Public mtSeed As Long
Public mtLevel As Long, mtOver As Long, mtWon As Long, mtBetween As Long
Public mtCell(0 To 11, 0 To 11) As Long         ' (row, col)
Public mtX As Long, mtZ As Long, mtVX As Long, mtVZ As Long
Public mtRoll As Long, mtPitch As Long
Public mtFalling As Long
Public mtCpRow As Long, mtCpCol As Long
Public mtGatesOpen As Long
Public mtFalls As Long, mtBumps As Long
Public mtTimeLeft As Long, mtTicks As Long, mtLevelTicks As Long
Public mtScore As Long
Public mtEv(0 To 15) As MtEvent
Public mtNEv As Long

Private levelCells(1 To 8, 0 To 11, 0 To 11) As Long
Private levelName(1 To 8) As String
Private d4r(0 To 3) As Long, d4c(0 To 3) As Long
Private d8r(0 To 7) As Long, d8c(0 To 7) As Long
' the route (MtPath): distances to the exit, valid while pathLevelKey is current
Private pdist(0 To 143) As Long
Private pqueue(0 To 143) As Long

Private Sub StoreLevel(ByVal n As Long, lv As Variant)
    Dim r As Long, c As Long, s As String
    For r = 0 To 11
        s = lv(r)
        For c = 0 To 11
            levelCells(n, r, c) = Asc(Mid$(s, c + 1, 1))
        Next c
    Next r
End Sub

Public Sub MtInit()
    Dim lv As Variant, nm As Variant, i As Long
    A3FixInit
    lv = Array( _
        "############", _
        "#S....#....#", _
        "#.##..#.##.#", _
        "#.##....##.#", _
        "#..........#", _
        "####.##.####", _
        "#....##....#", _
        "#.##....##.#", _
        "#.##.##.##.#", _
        "#....##...E#", _
        "#....##....#", _
        "############")
    StoreLevel 1, lv
    lv = Array( _
        "############", _
        "#S.........#", _
        "#.        .#", _
        "#. ...... .#", _
        "#. .####. .#", _
        "#. .#E .. .#", _
        "#. .#.##. .#", _
        "#. ...... .#", _
        "#.   .    .#", _
        "#..........#", _
        "#..........#", _
        "############")
    StoreLevel 2, lv
    lv = Array( _
        "############", _
        "#S.....    #", _
        "#####..    #", _
        "#   ...    #", _
        "#   ..######", _
        "#   .....  #", _
        "#####...   #", _
        "#    ...   #", _
        "#    ..#####", _
        "#     ....E#", _
        "#      ... #", _
        "############")
    StoreLevel 3, lv
    lv = Array( _
        "############", _
        "#S...#.....#", _
        "#....G.....#", _
        "#....#.....#", _
        "###.####G###", _
        "#..........#", _
        "#.  ....  .#", _
        "#.  .##.  .#", _
        "#.  .##.  .#", _
        "#....GG...E#", _
        "#..........#", _
        "############")
    StoreLevel 4, lv
    lv = Array( _
        "############", _
        "#S.........#", _
        "#..B...B...#", _
        "#..........#", _
        "#....B.....#", _
        "#.B......B.#", _
        "#....  ....#", _
        "#...    ...#", _
        "#.B..  ..B.#", _
        "#..........#", _
        "#....B....E#", _
        "############")
    StoreLevel 5, lv
    lv = Array( _
        "############", _
        "#S.ZZZZ....#", _
        "#..ZZZZ.##.#", _
        "#.......#  #", _
        "####.####  #", _
        "#....ZZZ...#", _
        "#.##.ZZZ.#.#", _
        "#.#  ...  ##", _
        "#.#  .#.   #", _
        "#....#E.   #", _
        "#....#..   #", _
        "############")
    StoreLevel 6, lv
    lv = Array( _
        "############", _
        "#S.        #", _
        "# .  .....E#", _
        "# .  .     #", _
        "# .  .  ...#", _
        "# ...C  .  #", _
        "#       .  #", _
        "#  ......  #", _
        "#  .       #", _
        "#  ......  #", _
        "#       .  #", _
        "############")
    StoreLevel 7, lv
    lv = Array( _
        "############", _
        "#S..B.  ...#", _
        "#.....  .G.#", _
        "###.##  .#.#", _
        "#  .....C#.#", _
        "#  .B.  ##.#", _
        "#  ...  ...#", _
        "#####.###G##", _
        "#.....B....#", _
        "#.  ....  .#", _
        "#E  .  .  .#", _
        "############")
    StoreLevel 8, lv
    nm = Array("FIRST ROLL", "THE MOAT", "ZIGZAG", "GATEHOUSE", "PINBALL", "SAND TRAP", "TIGHTROPE", "THE GAUNTLET")
    For i = 1 To 8
        levelName(i) = nm(i - 1)
    Next i
    d4r(0) = -1: d4c(0) = 0: d4r(1) = 1: d4c(1) = 0: d4r(2) = 0: d4c(2) = -1: d4r(3) = 0: d4c(3) = 1
    For i = 0 To 3
        d8r(i) = d4r(i): d8c(i) = d4c(i)
    Next i
    d8r(4) = -1: d8c(4) = -1: d8r(5) = -1: d8c(5) = 1: d8r(6) = 1: d8c(6) = -1: d8r(7) = 1: d8c(7) = 1
End Sub

Public Function MtLevelName(ByVal n As Long) As String
    MtLevelName = levelName(n)
End Function

Private Sub Ev(ByVal etype As Long, ByVal a As Long, ByVal b As Long)
    If mtNEv < MT_MAX_EVENTS Then
        mtEv(mtNEv).etype = etype
        mtEv(mtNEv).a = a
        mtEv(mtNEv).b = b
        mtNEv = mtNEv + 1
    End If
End Sub

Public Function MtCellX(ByVal col As Long) As Long
    MtCellX = ((col - 6) * MT_CELL + 20) * 65536
End Function

Public Function MtCellZ(ByVal row As Long) As Long
    MtCellZ = ((6 - row) * MT_CELL - 20) * 65536
End Function

Public Function MtColOf(ByVal x As Long) As Long
    Dim v As Long
    v = ShrA(x, 16) + 240
    If v < 0 Then MtColOf = -1 Else MtColOf = v \ MT_CELL
End Function

Public Function MtRowOf(ByVal z As Long) As Long
    Dim v As Long
    v = 240 - ShrA(z, 16)
    If v < 0 Then MtRowOf = -1 Else MtRowOf = v \ MT_CELL
End Function

Public Function MtAt(ByVal row As Long, ByVal col As Long) As Long
    If row < 0 Or col < 0 Or row >= MT_N Or col >= MT_N Then
        MtAt = CH_WALL
    Else
        MtAt = mtCell(row, col)
    End If
End Function

Public Function MtSolid(ByVal row As Long, ByVal col As Long) As Boolean
    Dim c As Long
    c = MtAt(row, col)
    MtSolid = (c = CH_WALL) Or (c = CH_GATE And mtGatesOpen = 0)
End Function

Private Sub PutAt(ByVal row As Long, ByVal col As Long)
    mtX = MtCellX(col)
    mtZ = MtCellZ(row)
    mtVX = 0
    mtVZ = 0
End Sub

Public Sub MtLoadLevel(ByVal lvl As Long)
    Dim r As Long, c As Long
    mtLevel = lvl
    For r = 0 To 11
        For c = 0 To 11
            mtCell(r, c) = levelCells(lvl, r, c)
            If mtCell(r, c) = CH_START Then
                mtCpRow = r
                mtCpCol = c
            End If
        Next c
    Next r
    PutAt mtCpRow, mtCpCol
    mtRoll = 0
    mtPitch = 0
    mtFalling = 0
    mtGatesOpen = 1
    mtTimeLeft = (50 + lvl * 10) * 25
    mtLevelTicks = 0
End Sub

Public Sub MtNewGame(ByVal seed As Long, ByVal lvl As Long)
    mtSeed = seed
    mtOver = 0: mtWon = 0: mtBetween = 0
    mtCpRow = 0: mtCpCol = 0
    mtFalls = 0: mtBumps = 0: mtTicks = 0: mtScore = 0
    mtNEv = 0
    If lvl < 1 Then lvl = 1
    If lvl > MT_LEVELS Then lvl = MT_LEVELS
    MtLoadLevel lvl
End Sub

Private Function Ease(ByVal v As Long, ByVal target As Long) As Long
    If v < target Then
        v = v + TILT_RATE
        If v > target Then v = target
    ElseIf v > target Then
        v = v - TILT_RATE
        If v < target Then v = target
    End If
    Ease = v
End Function

' the marble against the walls round it, and the bumpers
Private Sub Collide()
    Dim r0 As Long, c0 As Long, r As Long, c As Long, ch As Long
    Dim cx As Long, cz As Long, dx As Long, dz As Long, d As Long, vn As Long, nx As Long, nz As Long
    Const RAD As Long = 589824                  ' FROMI(MT_R)
    Const HALF As Long = 1310720                ' FROMI(MT_CELL / 2)
    Const REACH As Long = 1441792               ' FROMI(BUMPER_R + MT_R)
    r0 = MtRowOf(mtZ)
    c0 = MtColOf(mtX)
    For r = r0 - 1 To r0 + 1
        For c = c0 - 1 To c0 + 1
            ch = MtAt(r, c)
            cx = MtCellX(c)
            cz = MtCellZ(r)
            If ch = CH_BUMPER Then
                dx = mtX - cx
                dz = mtZ - cz
                d = FHypot(dx, dz)
                If d < REACH Then
                    If d < FONE Then
                        dx = FONE
                        d = FONE
                    End If
                    mtX = cx + FDiv(FMul(dx, REACH), d)
                    mtZ = cz + FDiv(FMul(dz, REACH), d)
                    vn = FDiv(FMul(mtVX, dx) + FMul(mtVZ, dz), d)
                    If vn < 0 Then
                        mtVX = mtVX - FDiv(FMul(2 * vn, dx), d)
                        mtVZ = mtVZ - FDiv(FMul(2 * vn, dz), d)
                    End If
                    mtVX = mtVX + FDiv(FMul(BUMP_KICK, dx), d)
                    mtVZ = mtVZ + FDiv(FMul(BUMP_KICK, dz), d)
                    mtBumps = mtBumps + 1
                    Ev MTE_BUMP, r, c
                End If
            ElseIf ch = CH_WALL Or (ch = CH_GATE And mtGatesOpen = 0) Then
                ' the nearest point of the cell's square
                If mtX < cx - HALF Then
                    nx = cx - HALF
                ElseIf mtX > cx + HALF Then
                    nx = cx + HALF
                Else
                    nx = mtX
                End If
                If mtZ < cz - HALF Then
                    nz = cz - HALF
                ElseIf mtZ > cz + HALF Then
                    nz = cz + HALF
                Else
                    nz = mtZ
                End If
                dx = mtX - nx
                dz = mtZ - nz
                If Abs(dx) < RAD And Abs(dz) < RAD Then
                    d = FHypot(dx, dz)
                    If d < RAD Then
                        If d < 256 Then              ' the middle inside the wall: out the way it came
                            If Abs(mtVX) > Abs(mtVZ) Then
                                If mtVX > 0 Then dx = -FONE Else dx = FONE
                                dz = 0
                            Else
                                If mtVZ > 0 Then dz = -FONE Else dz = FONE
                                dx = 0
                            End If
                            d = FONE
                        End If
                        mtX = mtX + FDiv(FMul(dx, RAD - d), d)
                        mtZ = mtZ + FDiv(FMul(dz, RAD - d), d)
                        vn = FDiv(FMul(mtVX, dx) + FMul(mtVZ, dz), d)
                        If vn < 0 Then
                            ' bounce back at 40%
                            mtVX = mtVX - FDiv(FMul(FMul(vn, 91750), dx), d)
                            mtVZ = mtVZ - FDiv(FMul(FMul(vn, 91750), dz), d)
                            If vn < -98304 Then Ev MTE_WALL, (-vn) \ 4096, 0
                        End If
                    End If
                End If
            End If
        Next c
    Next r
End Sub

Public Sub MtTick(ByVal inp As Long)
    Dim r As Long, c As Long, k As Long, ch As Long, isOpen As Long
    Dim ax As Long, az As Long, sp As Long, target As Long, bonus As Long
    If mtOver <> 0 Or mtWon <> 0 Then Exit Sub
    mtTicks = mtTicks + 1
    If mtBetween > 0 Then
        mtBetween = mtBetween - 1
        If mtBetween = 0 Then
            If mtLevel >= MT_LEVELS Then
                mtWon = 1
                Ev MTE_WIN, mtScore, 0
                Exit Sub
            End If
            MtLoadLevel mtLevel + 1
            Ev MTE_LEVEL, mtLevel, 0
        End If
        Exit Sub
    End If
    mtLevelTicks = mtLevelTicks + 1
    ' the gates
    If (mtLevelTicks \ MT_GATE_T) Mod 2 = 0 Then isOpen = 1 Else isOpen = 0
    If isOpen = 0 Then
        If MtAt(MtRowOf(mtZ), MtColOf(mtX)) = CH_GATE Then isOpen = 1      ' not on the marble
    End If
    If isOpen <> mtGatesOpen Then
        mtGatesOpen = isOpen
        Ev MTE_GATE, isOpen, 0
    End If
    ' the tilt
    If inp And MT_IN_RIGHT Then
        target = MT_TILT_MAX
    ElseIf inp And MT_IN_LEFT Then
        target = -MT_TILT_MAX
    Else
        target = 0
    End If
    mtRoll = Ease(mtRoll, target)
    If inp And MT_IN_UP Then
        target = MT_TILT_MAX
    ElseIf inp And MT_IN_DOWN Then
        target = -MT_TILT_MAX
    Else
        target = 0
    End If
    mtPitch = Ease(mtPitch, target)

    If mtFalling Then
        mtFalling = mtFalling - 1
        If mtFalling = 0 Then
            PutAt mtCpRow, mtCpCol
            Ev MTE_RESPAWN, mtCpRow, mtCpCol
        End If
    Else
        ax = FMul(FONE, FSinR(mtRoll))
        az = FMul(FONE, FSinR(mtPitch))
        r = MtRowOf(mtZ)
        c = MtColOf(mtX)
        ch = MtAt(r, c)
        mtVX = mtVX + ax
        mtVZ = mtVZ + az
        ' rolling friction; sand drags
        If ch = CH_SAND Then
            mtVX = mtVX - mtVX \ 8
            mtVZ = mtVZ - mtVZ \ 8
        Else
            mtVX = mtVX - mtVX \ 100
            mtVZ = mtVZ - mtVZ \ 100
        End If
        sp = FHypot(mtVX, mtVZ)
        If sp > VMAX Then
            mtVX = FDiv(FMul(mtVX, VMAX), sp)
            mtVZ = FDiv(FMul(mtVZ, VMAX), sp)
        End If
        For k = 0 To 3
            mtX = mtX + mtVX \ 4
            mtZ = mtZ + mtVZ \ 4
            Collide
        Next k
        r = MtRowOf(mtZ)
        c = MtColOf(mtX)
        ch = MtAt(r, c)
        If ch = CH_HOLE Then
            mtFalling = MT_FALL_T
            mtFalls = mtFalls + 1
            mtTimeLeft = mtTimeLeft - 75
            Ev MTE_FALL, r, c
        ElseIf ch = CH_CHECK And (mtCpRow <> r Or mtCpCol <> c) Then
            mtCpRow = r
            mtCpCol = c
            Ev MTE_CHECKPOINT, r, c
        ElseIf ch = CH_EXIT Then
            bonus = (mtTimeLeft \ 25) * 10 + 100 * mtLevel
            mtScore = mtScore + bonus
            mtBetween = MT_BETWEEN
            Ev MTE_EXIT, mtLevel, bonus
            Exit Sub
        End If
    End If
    mtTimeLeft = mtTimeLeft - 1
    If mtTimeLeft <= 0 Then
        mtTimeLeft = 0
        mtOver = 1
        Ev MTE_TIMEOUT, 0, 0
        Ev MTE_OVER, mtScore, 0
    End If
End Sub

' ---------- the autopilot ----------

' the next cell on the shortest route from (row, col) to the exit, through floor,
' sand, checkpoints and gates (open or not), round walls, bumpers and holes;
' steps: how far. Returns row * MT_N + col, or -1.
Public Function MtPath(ByVal row As Long, ByVal col As Long, steps As Long) As Long
    Dim head As Long, tail As Long, k As Long, er As Long, ec As Long, cur As Long
    Dim r As Long, c As Long, nr As Long, nc As Long, n As Long, ch As Long
    er = -1
    For k = 0 To 143
        pdist(k) = -1
        If mtCell(k \ 12, k Mod 12) = CH_EXIT Then
            er = k \ 12
            ec = k Mod 12
        End If
    Next k
    If er < 0 Then
        MtPath = -1
        Exit Function
    End If
    ' from the exit back
    pdist(er * 12 + ec) = 0
    pqueue(0) = er * 12 + ec
    tail = 1
    Do While head < tail
        cur = pqueue(head)
        head = head + 1
        r = cur \ 12
        c = cur Mod 12
        For k = 0 To 3
            nr = r + d4r(k)
            nc = c + d4c(k)
            ch = MtAt(nr, nc)
            If ch <> CH_WALL And ch <> CH_HOLE And ch <> CH_BUMPER Then
                n = nr * 12 + nc
                If pdist(n) < 0 Then
                    pdist(n) = pdist(cur) + 1
                    pqueue(tail) = n
                    tail = tail + 1
                End If
            End If
        Next k
    Loop
    MtPath = -1
    If row < 0 Or col < 0 Or row >= MT_N Or col >= MT_N Then Exit Function
    If pdist(row * 12 + col) < 0 Then Exit Function
    steps = pdist(row * 12 + col)
    If steps = 0 Then
        MtPath = row * 12 + col
        Exit Function
    End If
    For k = 0 To 3
        nr = row + d4r(k)
        nc = col + d4c(k)
        If nr >= 0 And nc >= 0 And nr < MT_N And nc < MT_N Then
            If pdist(nr * 12 + nc) = steps - 1 Then
                MtPath = nr * 12 + nc
                Exit Function
            End If
        End If
    Next k
End Function

Public Function MtBot() As Long
    Dim r As Long, c As Long, nxt As Long, nr As Long, nc As Long, steps As Long, s2 As Long, n2 As Long
    Dim tx As Long, tz As Long, dx As Long, dz As Long, d As Long, vdx As Long, vdz As Long
    Dim cap As Long, wx As Long, wz As Long, k As Long, sp As Long, inp As Long
    If mtOver <> 0 Or mtWon <> 0 Or mtBetween <> 0 Or mtFalling <> 0 Then Exit Function
    r = MtRowOf(mtZ)
    c = MtColOf(mtX)
    nxt = MtPath(r, c, steps)
    If nxt < 0 Then Exit Function
    nr = nxt \ 12
    nc = nxt Mod 12
    tx = MtCellX(nc)
    tz = MtCellZ(nr)
    ' the cell after next, if the route goes straight on: aim through
    n2 = MtPath(nr, nc, s2)
    If n2 >= 0 And n2 <> nxt Then
        If (n2 \ 12 - nr) = (nr - r) And (n2 Mod 12 - nc) = (nc - c) Then
            tx = MtCellX(n2 Mod 12)
            tz = MtCellZ(n2 \ 12)
        End If
    End If
    ' a gate ahead that is shut: wait short of it
    If MtAt(nr, nc) = CH_GATE And mtGatesOpen = 0 Then
        tx = MtCellX(c)
        tz = MtCellZ(r)
    End If
    dx = tx - mtX
    dz = tz - mtZ
    d = FHypot(dx, dz)
    ' slow beside holes
    cap = 104857                                ' FX(1.6)
    For k = 0 To 7
        If MtAt(r + d8r(k), c + d8c(k)) = CH_HOLE Then
            cap = 58982                         ' FX(0.9)
            Exit For
        End If
    Next k
    If d > 32768 Then
        If d \ 12 < cap Then sp = d \ 12 Else sp = cap
        vdx = FDiv(FMul(dx, sp), d)
        vdz = FDiv(FMul(dz, sp), d)
    End If
    ' tilt to bring the speed to that
    wx = vdx - mtVX
    wz = vdz - mtVZ
    If wx > 5242 Then
        inp = inp Or MT_IN_RIGHT
    ElseIf wx < -5242 Then
        inp = inp Or MT_IN_LEFT
    End If
    If wz > 5242 Then
        inp = inp Or MT_IN_UP
    ElseIf wz < -5242 Then
        inp = inp Or MT_IN_DOWN
    End If
    MtBot = inp
End Function

Public Function MtStateHash() As Long
    Dim h As Long
    h = FNV_START
    h = Fnv(h, mtScore): h = Fnv(h, mtLevel): h = Fnv(h, mtX): h = Fnv(h, mtZ)
    h = Fnv(h, mtVX): h = Fnv(h, mtVZ): h = Fnv(h, mtRoll): h = Fnv(h, mtPitch)
    h = Fnv(h, mtFalling): h = Fnv(h, mtFalls): h = Fnv(h, mtBumps): h = Fnv(h, mtTimeLeft)
    h = Fnv(h, mtTicks): h = Fnv(h, mtCpRow): h = Fnv(h, mtCpCol): h = Fnv(h, mtOver)
    h = Fnv(h, mtWon): h = Fnv(h, mtGatesOpen)
    MtStateHash = h
End Function

' the autopilot plays from a level: ticks played
Public Function MtAutoGame(ByVal seed As Long, ByVal lvl As Long, ByVal maxTicks As Long) As Long
    Dim t As Long
    MtNewGame seed, lvl
    Do While t < maxTicks And mtOver = 0 And mtWon = 0
        MtTick MtBot()
        mtNEv = 0
        t = t + 1
    Loop
    MtAutoGame = t
End Function
