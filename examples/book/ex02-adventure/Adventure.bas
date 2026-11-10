' Adventure.bas - a small text adventure (exercise 2 of the Boing BASIC manual).
' Rooms are a user-defined Type in an array, the inventory is a Collection, and the
' commands are parsed with Split and Select Case.
' Run it with:   boing run Adventure.bas
Option Explicit

' --- the world ---------------------------------------------------------------------------

Const NROOMS = 5
Const NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3

Type Room
    Name As String
    Description As String
    Exits(0 To 3) As Integer      ' the room to the north, east, south, west (0 = no way)
    Item As String                ' an object lying here ("" = none)
    Locked As Boolean             ' you need the key to get in
End Type

Dim rooms(1 To NROOMS) As Room
Dim here As Integer               ' the room you are in
Dim inventory As New Collection   ' what you carry (the key of each entry is its name)
Dim moves As Long
Dim finished As Boolean

Sub Main()
    Dim typed As String
    BuildWorld
    here = 1
    Print "THE LOST LAMP - a tiny adventure. Type HELP for the commands."
    Look
    Do Until finished
        Print
        Print "> ";
        Line Input typed
        DoCommand typed
    Loop
    Print "You made"; moves; "moves."
End Sub

' Fill in the rooms. Exits are room numbers: 0 means "no way".
Sub BuildWorld()
    SetRoom 1, "Hall", "A dusty hall. A staircase leads up to the north; a door opens to the east.", 2, 3, 0, 0, ""
    SetRoom 2, "Landing", "The top of the stairs. A cold draught comes from the west.", 0, 0, 1, 4, "key"
    SetRoom 3, "Kitchen", "Pots and pans everywhere. A heavy door leads east.", 0, 5, 0, 1, "pear"
    SetRoom 4, "Attic", "Cobwebs and old trunks under the roof.", 0, 2, 0, 0, "map"
    SetRoom 5, "Cellar", "A cool cellar. Something shines in the corner.", 0, 0, 0, 3, "lamp"
    rooms(5).Locked = True
End Sub

Sub SetRoom(n As Integer, roomName As String, text As String, n0 As Integer, e As Integer, s As Integer, w As Integer, thing As String)
    With rooms(n)
        .Name = roomName
        .Description = text
        .Exits(NORTH) = n0
        .Exits(EAST) = e
        .Exits(SOUTH) = s
        .Exits(WEST) = w
        .Item = thing
    End With
End Sub

' --- the parser --------------------------------------------------------------------------

' Split the command into a verb and a noun ("take the key" -> "take", "key") and act on it.
Sub DoCommand(ByVal typed As String)
    Dim words() As String, verb As String, noun As String, i As Integer

    typed = LCase(Trim(typed))
    If typed = "" Then Exit Sub
    words = Split(typed, " ")
    verb = words(0)
    For i = 1 To UBound(words)              ' the noun is the last word that is not "the"
        If words(i) <> "" And words(i) <> "the" Then noun = words(i)
    Next i
    moves = moves + 1

    Select Case verb
    Case "n", "north": Go NORTH
    Case "e", "east": Go EAST
    Case "s", "south": Go SOUTH
    Case "w", "west": Go WEST
    Case "go", "walk"
        Select Case noun
        Case "n", "north": Go NORTH
        Case "e", "east": Go EAST
        Case "s", "south": Go SOUTH
        Case "w", "west": Go WEST
        Case Else: Print "Go where?"
        End Select
    Case "l", "look": Look
    Case "take", "get": Take noun
    Case "drop": Drop noun
    Case "i", "inv", "inventory": ShowInventory
    Case "eat": Eat noun
    Case "help", "?"
        Print "Commands: N E S W (or GO NORTH...), LOOK, TAKE x, DROP x, INVENTORY, EAT x, QUIT"
    Case "quit", "q": finished = True
    Case Else
        Print "I don't know how to " & verb & "."
        moves = moves - 1                   ' a mistake doesn't count as a move
    End Select
End Sub

' --- the actions -------------------------------------------------------------------------

Sub Look()
    Print UCase(rooms(here).Name)
    Print rooms(here).Description
    If rooms(here).Item <> "" Then Print "You can see a " & rooms(here).Item & " here."
    Print "Exits:" & ExitList()
End Sub

Function ExitList() As String
    Dim d As Integer
    For d = NORTH To WEST
        If rooms(here).Exits(d) <> 0 Then ExitList = ExitList & " " & Choose(d + 1, "north", "east", "south", "west")
    Next d
End Function

Sub Go(direction As Integer)
    Dim target As Integer
    target = rooms(here).Exits(direction)
    If target = 0 Then
        Print "You can't go that way."
    ElseIf rooms(target).Locked And Not Carrying("key") Then
        Print "The door is locked."
    Else
        If rooms(target).Locked Then
            Print "You unlock the door with the key."
            rooms(target).Locked = False
        End If
        here = target
        Look
    End If
End Sub

Sub Take(thing As String)
    If thing = "" Then
        Print "Take what?"
    ElseIf rooms(here).Item <> thing Then
        Print "There is no " & thing & " here."
    Else
        inventory.Add thing, thing          ' the item, and its name as the key
        rooms(here).Item = ""
        Print "Taken: " & thing & "."
        If thing = "lamp" Then
            Print "You have found the lost lamp. Well done!"
            finished = True
        End If
    End If
End Sub

Sub Drop(thing As String)
    If Not Carrying(thing) Then
        Print "You are not carrying a " & thing & "."
    ElseIf rooms(here).Item <> "" Then
        Print "There is no room here: the " & rooms(here).Item & " is in the way."
    Else
        inventory.Remove thing
        rooms(here).Item = thing
        Print "Dropped: " & thing & "."
    End If
End Sub

Sub Eat(thing As String)
    If thing <> "pear" Or Not Carrying("pear") Then
        Print "You can't eat that."
    Else
        inventory.Remove "pear"
        Print "Delicious. You feel ready for anything."
    End If
End Sub

Sub ShowInventory()
    Dim thing As Variant
    If inventory.Count = 0 Then
        Print "You are carrying nothing."
        Exit Sub
    End If
    Print "You are carrying:"
    For Each thing In inventory
        Print "  a " & thing
    Next
End Sub

' True when the inventory has an entry with this key. Item() on a missing key is error 5,
' so the error tells us the answer.
Function Carrying(thing As String) As Boolean
    Dim x As Variant
    On Error GoTo NotThere
    x = inventory(thing)
    Carrying = True
    Exit Function
NotThere:
    Carrying = False
End Function
