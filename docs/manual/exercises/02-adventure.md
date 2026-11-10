# Exercise 2: A text adventure

In this exercise you write "The Lost Lamp", a tiny text adventure: you walk between rooms,
pick things up, unlock a door and find the lamp. It is a good way to learn how to keep data
in your own types and arrays, and how to understand what the player types.

**Goal:** a five-room adventure that understands commands such as `north`, `go east`,
`take the key`, `drop map`, `inventory` and `quit`.

**What you will learn:**

- a user-defined type (`Type ... End Type`) with an array inside it
- an array of a user-defined type, and `With ... End With`
- a `Collection`: `Add`, `Remove`, `Count`, keys, `For Each`
- catching a run-time error with `On Error GoTo`
- a command parser built with `Split`, `LCase`, `Trim` and `Select Case`
- `Choose` and `Const` lists

The full solution is `examples/book/ex02-adventure/Adventure.bas`.

## Step 1: A room is a Type

A room has a name, a description and four exits. Instead of keeping these in separate
variables, define a **type** that holds them all:

<!-- run -->
```basic
Option Explicit

Type Room
    Name As String
    Description As String
    Exits(0 To 3) As Integer      ' north, east, south, west: a room number, 0 = no way
End Type

Dim hall As Room
hall.Name = "Hall"
hall.Description = "A dusty hall."
hall.Exits(1) = 2                 ' east leads to room 2
Print hall.Name & ": " & hall.Description
Print "East goes to room"; hall.Exits(1)
```

```output
Hall: A dusty hall.
East goes to room 2 
```

`Type Room ... End Type` says what a `Room` is made of; `Dim hall As Room` makes one. The
parts (fields) are reached with a dot: `hall.Name`. A field can be an array, like `Exits`.
A `Type` must be declared at module level (outside any `Sub` or `Function`).

## Step 2: An array of rooms, and walking between them

`Dim rooms(1 To 3) As Room` makes three rooms, numbered 1 to 3. Each exit holds the number of
the room it leads to, so walking is just `here = rooms(here).Exits(d)`. The output below is
for the moves `e n w n x s q`.

<!-- run stdin="e\nn\nw\nn\nx\ns\nq" -->
```basic
Option Explicit

Type Room
    Name As String
    Exits(0 To 3) As Integer      ' north, east, south, west
End Type

Dim rooms(1 To 3) As Room
Dim here As Integer, d As Integer, typed As String

rooms(1).Name = "Hall":    rooms(1).Exits(0) = 2: rooms(1).Exits(1) = 3
rooms(2).Name = "Landing": rooms(2).Exits(2) = 1
rooms(3).Name = "Kitchen": rooms(3).Exits(3) = 1

here = 1
Print "Type n, e, s or w to walk, q to quit."
Do
    Print "You are in the " & rooms(here).Name & "."
    Line Input typed
    d = InStr("nesw", LCase(typed)) - 1      ' "n" -> 0, "e" -> 1 ... not found -> -1
    If typed = "q" Then Exit Do
    If d < 0 Or Len(typed) <> 1 Then
        Print "Type n, e, s or w."
    ElseIf rooms(here).Exits(d) = 0 Then
        Print "You can't go that way."
    Else
        here = rooms(here).Exits(d)
    End If
Loop
Print "Bye."
```

```output
Type n, e, s or w to walk, q to quit.
You are in the Hall.
You are in the Kitchen.
You can't go that way.
You are in the Kitchen.
You are in the Hall.
You are in the Landing.
Type n, e, s or w.
You are in the Landing.
You are in the Hall.
Bye.
```

`InStr("nesw", letter) - 1` turns a direction letter into the number of its exit, a small
trick that saves a `Select Case`. The map is just numbers: draw it on paper first (the hall,
the landing to its north, the kitchen to its east) and the numbers follow.

## Step 3: The inventory is a Collection

The things you carry change all the time. An array has a fixed size; a **Collection** grows
and shrinks as you add and remove items, and can find an item by a **key** (a name).

<!-- run -->
```basic
Option Explicit
Dim bag As New Collection
Dim thing As Variant

bag.Add "key", "key"              ' the item, and a key to find it by
bag.Add "map", "map"
bag.Add "lamp", "lamp"
Print "Items:"; bag.Count
For Each thing In bag
    Print "  " & thing
Next
bag.Remove "map"                  ' by key (or by position: bag.Remove 1)
Print "First item: " & bag(1) & ", items now:"; bag.Count
Print "Have a map? "; Has(bag, "map")
Print "Have a lamp? "; Has(bag, "LAMP")    ' keys ignore case

Function Has(c As Collection, k As String) As Boolean
    Dim x As Variant
    On Error GoTo Missing             ' asking for a missing key is error 5
    x = c(k)
    Has = True
    Exit Function
Missing:
End Function
```

```output
Items: 3 
  key
  map
  lamp
First item: key, items now: 2 
Have a map? False
Have a lamp? True
```

| Collection member | What it does |
|---|---|
| `c.Add item [, key]` | adds an item at the end, with an optional key (a String) |
| `c(i)`, `c.Item(i)` | the item at position i (from 1), or with the key i when i is a String |
| `c.Count` | how many items there are |
| `c.Remove i` | removes the item at position i, or with key i |
| `For Each x In c ... Next` | goes through the items in order; `x` must be a Variant (or an object variable) |

- `Dim bag As New Collection` makes the collection the first time `bag` is used.
- Keys ignore the difference between capitals and small letters. Adding a key that is already
  there is error 457; asking for a key that is not there is error 5.
- There is no "Contains" method, so `Has` asks for the item and catches the error.
  `On Error GoTo Missing` sends any run-time error to the line labelled `Missing:`, where the
  function ends with its value still `False`. Without the handler, error 5 would stop the
  program.

## Step 4: Understanding commands

Players type `take the key`, `Take  key` or `get key`. The parser makes them all the same:
it changes the text to lower case, removes spaces at the ends, cuts it into words with
`Split` and takes the first word as the **verb** and the last useful word as the **noun**.

<!-- run stdin="north\nTake  the lamp\nget\ndance wildly\nquit" -->
```basic
Option Explicit
Dim typed As String

Do
    Line Input typed
    typed = LCase(Trim(typed))
    If typed = "quit" Then Exit Do
    Parse typed
Loop

' Cut a command into its verb and its noun, and say what it means.
Sub Parse(ByVal typed As String)
    Dim words() As String, verb As String, noun As String, i As Integer
    If typed = "" Then Exit Sub
    words = Split(typed, " ")
    verb = words(0)
    For i = 1 To UBound(words)         ' the noun: the last word that isn't "the" or ""
        If words(i) <> "" And words(i) <> "the" Then noun = words(i)
    Next i
    Select Case verb
    Case "n", "north", "e", "east", "s", "south", "w", "west"
        Print "You walk " & Left(verb, 1) & "."
    Case "take", "get"
        If noun = "" Then Print "Take what?" Else Print "You take the " & noun & "."
    Case "look", "l"
        Print "You look around."
    Case Else
        Print "I don't know how to " & verb & "."
    End Select
End Sub
```

```output
You walk n.
You take the lamp.
Take what?
I don't know how to dance.
```

`ByVal typed As String` gives the Sub its own copy of the text. Without `ByVal`, a parameter
is passed **by reference**: the Sub works on the caller's variable itself, and changing it
would change the caller's too.

## Step 5: The whole adventure

The solution puts these pieces together. The rooms get a few more fields: an item lying in
the room and whether its door is locked.

<!-- project: examples/book/ex02-adventure/Adventure.bas -->
```basic
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
```

The constants `NORTH` to `WEST` make the code readable: `Go NORTH` rather than `Go 0`.
`SetRoom` fills in one room. `With rooms(n)` lets the lines inside it leave out
`rooms(n)`: `.Name` means `rooms(n).Name`.

<!-- project: examples/book/ex02-adventure/Adventure.bas -->
```basic
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
```

`Look` prints the room and its exits. `ExitList` builds the list of exits with `Choose`, which
picks its first, second, third ... argument by number:

<!-- project: examples/book/ex02-adventure/Adventure.bas -->
```basic
Function ExitList() As String
    Dim d As Integer
    For d = NORTH To WEST
        If rooms(here).Exits(d) <> 0 Then ExitList = ExitList & " " & Choose(d + 1, "north", "east", "south", "west")
    Next d
End Function
```

`Go` moves the player, and opens the locked cellar door when the key is in the inventory:

<!-- project: examples/book/ex02-adventure/Adventure.bas -->
```basic
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
```

`Take` moves the room's item into the inventory (`inventory.Add thing, thing`), `Drop` the
other way (`inventory.Remove thing`), and `ShowInventory` lists it with `For Each`. Taking the
lamp sets `finished`, which ends the main loop:

<!-- project: examples/book/ex02-adventure/Adventure.bas -->
```basic
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
```

A short game (the answers typed are left out, as before):

```text
> HALL
A dusty hall. A staircase leads up to the north; a door opens to the east.
Exits: north east
...
> You unlock the door with the key.
CELLAR
A cool cellar. Something shines in the corner.
You can see a lamp here.
Exits: west

> Taken: lamp.
You have found the lost lamp. Well done!
You made 18 moves.
```

## Running it

From a Shell in the solution's drawer:

```sh
boing run Adventure.bas
```

A program can be a single `.bas` file without a project: `boing run`, `boing build` and
`boing check` take either. To play the walkthrough in `input.txt` without typing it:

```sh
boing run Adventure.bas < input.txt
```

`expected.out` is what that prints; the manual's tests compare the two.

In AmiForge, make a **Boing BASIC Console App** project, replace the code of its `Main.bas`
with the adventure, and press **Ctrl-F5**. The game runs in a console window; type your
commands there.

## Try this

1. Add two rooms of your own and an item in each. Draw the map first.
2. Make the lamp light the cellar: without the lamp the cellar says "It is too dark to see."
   (Give the lamp to the player somewhere else, and put a treasure in the cellar.)
3. Let a room hold several items: change `Item As String` to `Items As Collection` (make
   each one with `Set rooms(n).Items = New Collection` in `SetRoom`), and list them all in
   `Look`.
4. Add `examine x` with a description for each item, kept in a second Collection whose keys
   are the item names.
5. Save and load the game with `Open ... For Output` and `Write #` / `Input #` (see
   [Files](../10-files.md)).

## See also

- [Data, variables and types](../04-data.md) (Type, arrays, Const),
  [Classes and collections](../11-classes.md), [Errors](../08-errors.md)
- Previous: [Exercise 1: Console programs](01-console.md).
  Next: [Exercise 3: Classes and events](03-classes.md)
