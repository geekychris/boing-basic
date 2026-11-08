' A tiny text adventure: rooms as a UDT array, items in a Collection, commands from Input
Option Explicit

Type Room
    Name As String
    Desc As String
    Exits(0 To 3) As Integer      ' N E S W: room index or -1
End Type

Const NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3
Dim rooms(1 To 4) As Room
Dim itemsAt As New Collection       ' key: item name, value: room index (0 = carried)
Dim here As Integer, moves As Integer

Sub Connect(ByVal a As Integer, ByVal dir As Integer, ByVal b As Integer)
    rooms(a).Exits(dir) = b
    rooms(b).Exits((dir + 2) Mod 4) = a
End Sub

Sub Setup()
    Dim i As Integer, d As Integer
    For i = 1 To 4
        For d = 0 To 3: rooms(i).Exits(d) = -1: Next
    Next
    rooms(1).Name = "Hall": rooms(1).Desc = "A dusty hall."
    rooms(2).Name = "Kitchen": rooms(2).Desc = "It smells of old soup."
    rooms(3).Name = "Garden": rooms(3).Desc = "Overgrown roses everywhere."
    rooms(4).Name = "Vault": rooms(4).Desc = "Gold glitters in the dark!"
    Connect 1, NORTH, 2
    Connect 1, EAST, 3
    Connect 3, NORTH, 4
    itemsAt.Add 2, "lamp"
    itemsAt.Add 3, "key"
    here = 1
End Sub

Function DirIndex(ByVal w As String) As Integer
    Select Case LCase$(w)
        Case "n", "north": DirIndex = NORTH
        Case "e", "east": DirIndex = EAST
        Case "s", "south": DirIndex = SOUTH
        Case "w", "west": DirIndex = WEST
        Case Else: DirIndex = -1
    End Select
End Function

Function ItemsHere(ByVal r As Integer) As String
    Dim names As Variant, s As String, k As Variant
    names = Array("lamp", "key")
    For Each k In names
        If itemsAt(k) = r Then s = s & " " & k
    Next
    ItemsHere = Trim$(s)
End Function

Sub Look()
    Dim s As String
    Print rooms(here).Name; ": "; rooms(here).Desc
    s = ItemsHere(here)
    If s <> "" Then Print "You see: "; s
End Sub

Sub Go(ByVal d As Integer)
    Dim target As Integer
    If d < 0 Then Print "Which way?": Exit Sub
    target = rooms(here).Exits(d)
    If target = -1 Then Print "You can't go that way.": Exit Sub
    If target = 4 And itemsAt("key") <> 0 Then Print "The vault is locked.": Exit Sub
    here = target
    moves = moves + 1
    Look
End Sub

Sub Take(ByVal what As String)
    On Error GoTo nothing_here
    If itemsAt(what) <> here Then GoTo nothing_here
    itemsAt.Remove what
    itemsAt.Add 0, what
    Print "Taken: "; what
    Exit Sub
nothing_here:
    Print "No "; what; " here."
End Sub

Dim cmd As String, verb As String, arg As String, sp As Integer
Setup
Look
Do
    Line Input "> ", cmd
    Print cmd
    cmd = Trim$(cmd)
    sp = InStr(cmd, " ")
    If sp > 0 Then verb = LCase$(Left$(cmd, sp - 1)): arg = Mid$(cmd, sp + 1) Else verb = LCase$(cmd): arg = ""
    Select Case verb
        Case "look", "l": Look
        Case "go": Go DirIndex(arg)
        Case "n", "e", "s", "w": Go DirIndex(verb)
        Case "take", "get": Take arg
        Case "inv", "i"
            If ItemsHere(0) = "" Then Print "You carry nothing." Else Print "You carry: "; ItemsHere(0)
        Case "quit", "q": Exit Do
        Case "": ' nothing
        Case Else: Print "I don't understand '"; verb; "'."
    End Select
    If here = 4 Then Print "You win in"; moves; "moves!": Exit Do
Loop
Print "Bye."
