# Appendix C: Error messages

This appendix lists the run-time errors that Boing BASIC raises, with their numbers, messages
and typical causes, and then the most common compile-time messages from `boing check`, with
examples. How to handle errors is described in [Errors and error handling](08-errors.md).

## Run-time errors

When a run-time error is not handled, the program prints

```text
file:line: runtime error number: message
```

and ends with return code 20. Inside an error handler, `Err.Number` is the number and
`Err.Description` the message. This program provokes a few of them:

<!-- run -->
```basic
Sub Try(ByVal what As Integer)
    Dim a(3) As Integer, n As Integer, v As Variant, o As Object, s As String
    On Error GoTo h
    Select Case what
    Case 1: n = 1 \ n
    Case 2: n = 99999
    Case 3: a(4) = 1
    Case 4: n = "many"
    Case 5: s = Left("abc", -1)
    Case 6: o.Show
    Case 7: v = Null: s = v
    Case 8: Open "no-such-file.txt" For Input As #1
    End Select
    Exit Sub
h:
    Print Err.Number; Err.Description
End Sub

Dim i As Integer
For i = 1 To 8
    Try i
Next
```

```output
 11 Division by zero
 6 Overflow
 9 Subscript out of range
 13 Type mismatch
 5 Invalid procedure call or argument
 91 Object variable or With block variable not set
 94 Invalid use of Null
 53 File not found
```

### The errors the runtime raises

| No. | Message | Typical cause |
|---|---|---|
| 3 | Return without GoSub | a `Return` that was not reached through `GoSub` (often: falling into a `GoSub` routine at the end of the main code) |
| 5 | Invalid procedure call or argument | an argument out of range: `Left(s, -1)`, `Mid(s, 0)`, `Chr(300)`, `Asc("")`, `Sqr(-1)`, `Log(0)`, `Shl(x, 32)`, `MonthName(13)`, an unknown interval in `DateAdd`, `Dir` without a pattern before any search, an empty name in `SaveSetting`; a runtime object method given a bad value; a missing key in a `Collection`; `App.OpenScreen` while the program's screen is open, or an `App.ReadArgs` template of more than 32 items |
| 6 | Overflow | a result too big for its type: `Dim n As Integer: n = 40000`, `CInt(1E6)`, a Long calculation beyond 2147483647, a Double result that is infinite or not a number |
| 7 | Out of memory | the program or a runtime object could not get memory; also too many items for some runtime tables (menu items, AppIcons) |
| 9 | Subscript out of range | an array index outside the array's bounds, an array element before `ReDim`, an index of a control array or list that does not exist |
| 10 | This array is fixed or temporarily locked | `ReDim` or `Erase` of an array while `For Each` is going through it; assigning to a fixed-size array |
| 11 | Division by zero | `/`, `\` or `Mod` by 0; `MulDiv(a, b, 0)` |
| 13 | Type mismatch | a value that cannot be converted: `CInt("abc")`, `n = "many"`, an object where a number is needed; assigning an object of the wrong class; `For Each` over something that is not an array or collection; `Input #` reading letters into a number |
| 14 | Out of string space | a string could not be allocated (memory is full) |
| 18 | User interrupt occurred | Ctrl-C or a break signal (see [Errors](08-errors.md#ctrl-c-stopping-a-running-program)) |
| 20 | Resume without error | `Resume` when no error is being handled, usually by falling into the handler without an `Exit Sub` before it |
| 28 | Out of stack space | recursion that goes too deep; more than 64 nested `GoSub`s |
| 35 | Sub or Function not defined | calling a procedure that has no body (rare: most such mistakes are found when compiling) |
| 48 | Library could not be opened | a `Declare`d function's library could not be opened: a misspelt library name, a library that is not installed, a `Version` that is too high; any `Declare` call on a host computer |
| 51 | Internal error | a fault inside Boing BASIC itself; please report it with the program |
| 52 | Bad file name or number | a file number that is not open, or not from 1 to 511 |
| 53 | File not found | `Open ... For Input` (or `Binary`/`Random` with `Access Read`) of a missing file; `Kill`, `FileLen`, `FileCopy` or `Name` of a missing file; a picture, sound or module file that is not there |
| 54 | Bad file mode | the file was opened for something else: `Print #` to an `Input` file, `Line Input #` from an `Output` file, `Get`/`Put` on a text file |
| 55 | File already open | `Open` with a file number that is still open |
| 57 | Device I/O error | writing to a file failed, a file could not be read completely |
| 58 | File already exists | `Name` to an existing name; `MkDir` of an existing directory |
| 61 | Disk full | the disk is full while writing or copying |
| 62 | Input past end of file | `Input #`, `Line Input #` or `Input()` after the end of the file; `Input` on the console after the end of input |
| 63 | Bad record number | a record or position below 1 in `Get`, `Put` or `Seek` |
| 67 | Too many files | `FreeFile` when files 1 to 255 are all open |
| 68 | Device unavailable | a volume or device that is not mounted (AmigaOS) |
| 70 | Permission denied | a protected file or disk (delete-, write- or read-protected), or a file in use by another program |
| 75 | Path/File access error | a file that cannot be opened or made (bad path, empty name); `RmDir` of a directory that is not empty; other file system failures |
| 76 | Path not found | a directory in the path does not exist; `ChDir` or `RmDir` of a missing directory |
| 91 | Object variable or With block variable not set | using an object variable that is `Nothing` (`Dim o As Object: o.Show`) |
| 92 | For loop not initialized | `For Each` over an empty Variant or an array that was never dimensioned |
| 93 | Invalid pattern string | a `Like` pattern with a `[` that is not closed |
| 94 | Invalid use of Null | `Null` where a value is needed: assigning it to a String or number, `Str(Null)`, `Hex(Null)`, `String(n, Null)` |
| 364 | Object was unloaded | using a control of a form that has been unloaded |
| 380 | Invalid property value | a property or method argument out of range on a runtime object: a Canvas size above 4096, an unknown model, sound or grid number, a bad drawing mode |
| 383 | Set not supported (read-only property) | assigning to a read-only property of a runtime object |
| 424 | Object required | an object operation (`Set`, `Is`, a method call) on something that is not an object; `Load` or `Unload` of something that is not a form |
| 429 | ActiveX component can't create object | `CreateObject` with a class name the runtime does not know; a control type that does not exist |
| 438 | Object doesn't support this property or method | a late-bound member name (on an `Object` or `Variant`) that the object does not have, often a typing mistake; a Workbench-only `App` member on a host |
| 449 | Argument not optional | a required argument left out of a late-bound call or a runtime object method |
| 450 | Wrong number of arguments or invalid property assignment | too many or too few arguments in a late-bound call; `TagList` with an odd number of arguments |
| 453 | Library function not found | a `Declare`d function that does not exist in a library that did open (wrong function name or `Alias`) |
| 457 | This key is already associated with an element of this collection | `Collection.Add` with a key that is already used |
| 458 | Variable uses a type Boing BASIC does not support here | passing or returning a user-defined type through a late-bound call |
| 481 | Invalid picture | a picture file that cannot be loaded (not a picture, or a format the datatypes cannot read) |

Your own errors (from `Err.Raise` or `Error`) can have any number from 1 to 65535, or
`vbObjectError` plus a number. A number with no standard message, such as 1000, has the message
"Application-defined or object-defined error" unless you give a description.

### Other standard messages

`Error(n)` and `Err.Raise n` know the standard messages of these numbers too, although Boing
BASIC itself does not raise them: 16 Expression too complex, 17 Can't perform requested
operation, 47 Too many library clients, 49 Bad library calling convention, 59 Bad record
length, 71 Disk not ready, 74 Can't rename with different drive, 381 Invalid property array
index, 382 Set not supported at runtime, 385 Need property array index, 387 Set not permitted,
393 Get not supported at runtime, 394 Get not supported (write-only property), 422 Property not
found, 423 Property or method not found, 430 Class does not support Automation or does not
support expected interface, 440 Automation error, 445 Object doesn't support this action, 446
Object doesn't support named arguments, 448 Named argument not found, 451 Property let
procedure not defined and property get procedure did not return an object, 455 Code resource
lock error, 459 Object or class does not support the set of events, 460 Invalid clipboard
format, 735 Can't save file to TEMP, 744 Search text not found, 746 Replacements too long.

## Compile-time errors

`boing check` (and `boing run` and `boing build` before they start) prints compile-time errors
as

```text
file:line:column: error: message
```

where the column is the position of the mistake in the line, counting from 1. Warnings have the
same form with `warning:` and do not stop the program. A mistake in the shape of a statement
(the first group below) stops the check at that point; the other errors are all reported in one
go. The most common messages, with an example of each:

### Syntax

**expected ..., found ...**: a statement is not finished, or has something in the wrong place.

<!-- error: expected ')', found end of line -->
```basic
Print Left("Amiga", 2
```

```text
prog.bas:1:22: error: expected ')', found end of line
```

**expected 'End If', found end of file** (also `'Next'`, `'Loop'`, `'End Sub'`...): a block
was opened but not closed. The line is where the file ends, so look for the `If` (or `For`,
`Do`, `Sub`) that has no end.

<!-- error: expected 'End If' -->
```basic
Dim n As Integer
If n = 0 Then
    Print "zero"
```

**expected expression, found ...**: a value is missing, often after an operator or `=`.

<!-- error: expected expression -->
```basic
Dim n As Integer
n = 5 *
```

**unterminated string**: a string has no closing `"` on its line.

<!-- error: unterminated string -->
```basic
Print "Hello
```

**'Next j' does not match 'For i'**: loops closed in the wrong order.

<!-- error: 'Next j' does not match 'For i' -->
```basic
Dim i As Integer, j As Integer
For i = 1 To 3
    For j = 1 To 3
    Next i
Next j
```

**... is not allowed inside a procedure**: `Sub`, `Function`, `Type`, `Declare` and the like
inside another procedure, usually because an `End Sub` is missing above.

<!-- error: is not allowed inside a procedure -->
```basic
Sub One()
    Print "one"
Sub Two()
    Print "two"
End Sub
```

### Names

**variable 'x' is not defined**: under `Option Explicit`, a name that was not declared with
`Dim` (often a typing mistake).

<!-- error: variable 'totl' is not defined -->
```basic
Option Explicit
Dim total As Long
totl = 5
```

**Sub, Function or array 'x' is not defined**: a call of a procedure or function that does not
exist, or an array that was not declared. Check the spelling, and that the procedure is
`Public` if it is in another module.

<!-- error: Sub, Function or array 'Lenn' is not defined -->
```basic
Print Lenn("abc")
```

**ambiguous name 'x': it is a Public procedure in modules A and B (write A.x)**: two modules
have a `Public` procedure of that name, and a third module uses it without saying which. Write
the module name in front, as the message suggests ([Procedures](05-procedures.md#qualified-names)).
Inside module A or B, the name alone means that module's own procedure.

**cannot find include file 'x' (looked beside the program, in $BOING_BINDINGS and in the
bindings directory)**: an `#Include` line or a `Uses=` key names a file that isn't in any of
those places. Check the spelling, or set `BOING_BINDINGS`
([Procedures](05-procedures.md#sharing-code-include-and-uses)).

<!-- error: cannot find include file 'utils.bi' -->
```basic
#Include "utils.bi"
Print "never compiled"
```

**#Include is not allowed in a class module: put it in a standard module**: include the file in
any standard module; its Public declarations are visible in the class too.

**the form 'x' has the same name as the module / class / procedure 'x'**: a form's window name
(`name=` in the `.afg`) is also the name of another module, a class, or a `Public` procedure or
variable. Rename one of them ([Forms](12-forms.md#reaching-a-form-from-other-modules)). A
window may have the name of its own code-behind module.

**'x' is already declared in this procedure** / **'x' is already defined**: the same name
declared twice.

<!-- error: 'n' is already declared in this procedure -->
```basic
Sub Main()
    Dim n As Integer
    Dim n As Long
End Sub
```

**label 'x' is not defined in this procedure**: a `GoTo`, `GoSub`, `On Error GoTo` or `Resume`
to a label that is not in the same procedure.

<!-- error: label 'handler' is not defined in this procedure -->
```basic
Sub Main()
    On Error GoTo handler
End Sub
```

**'x' is not a member of ...** / **type 'T' has no field 'f'**: a misspelt member of a runtime
class or a field of a user-defined type.

<!-- error: type 'Point' has no field 'Z' -->
```basic
Type Point
    X As Long
    Y As Long
End Type
Dim p As Point
p.Z = 1
```

### Types and arguments

**type mismatch: cannot convert A to B**: a value of a type that cannot become the type needed,
for example a user-defined type where a number is wanted.

<!-- error: type mismatch: cannot convert Point to Long -->
```basic
Type Point
    X As Long
    Y As Long
End Type
Dim p As Point, n As Long
n = p
```

**ByRef argument type mismatch: Integer variable passed for Long parameter 'n'**: a variable
passed to a `ByRef` parameter (the default) must have exactly the parameter's type. Declare the
variable with that type, make the parameter `ByVal`, or pass a copy (`CLng(x)` or `(x)`).

<!-- error: ByRef argument type mismatch -->
```basic
Sub Twice(n As Long)
    n = n * 2
End Sub
Dim count As Integer
Twice count
```

**wrong number of arguments to 'F'** / **too many arguments to 'F' (expected n)** /
**argument 'x' of 'F' is not optional**: a call with too few or too many arguments.

<!-- error: argument 'b' of 'Add' is not optional -->
```basic
Function Add(ByVal a As Long, ByVal b As Long) As Long
    Add = a + b
End Function
Print Add(1)
```

**'S' is a Sub and does not return a value**: a Sub used as if it were a Function. Make it a
`Function`, or call it as a statement.

<!-- error: 'Hello' is a Sub and does not return a value -->
```basic
Sub Hello()
    Print "hello"
End Sub
Dim x As Variant
x = Hello()
```

**Set needs an object variable ('s' is String)** / **use Set to assign an object reference**:
`Set` is for objects only, and objects need `Set`.

<!-- error: use Set to assign an object reference -->
```basic
Dim c As Collection
c = New Collection
```

**'x' is not an array** / **wrong number of dimensions for array 'a'**: indexing something that
is not an array, or with the wrong number of indexes.

<!-- error: wrong number of dimensions for array 'grid' -->
```basic
Dim grid(10, 10) As Integer
grid(1) = 5
```

### Statements in the wrong place

**Exit For outside a For loop** (also `Exit Do`, `Exit Sub`, `Exit Function`): an `Exit` with
nothing to leave.

<!-- error: Exit Do outside a Do loop -->
```basic
Dim i As Integer
For i = 1 To 3
    Exit Do
Next
```

**'Me' is only valid in a class module**, **Event is only allowed in a class module**,
**WithEvents is only allowed at module level**: class features used in the wrong kind of
module; see [Classes](11-classes.md).

**overflow (error 6) in a constant expression**: a Single or Double calculation made only of
constants gives a result too big for its type. Boing BASIC works such calculations out when it
compiles, so the overflow that would be run-time error 6 with variables is found by `boing
check` (see [Expressions](07-expressions.md#overflow)).

<!-- error: overflow (error 6) in a constant expression -->
```basic
Const HUGE = 1E308 * 10
```

**ByRef parameter 'x' of Declare F needs a Long variable (or declare it ByVal)**: a numeric
`ByRef` parameter of a `Declare`d function passes the address of a variable, so the argument
must be a variable of exactly that type, not a constant, an expression or a variable of another
type (see [AmigaOS](17-amigaos.md#arguments)).

**the module 'm' hides the built-in class C: rename the module**: one of your modules has the
name of a built-in class, usually because of its file name (`http.bas` is the module `http`,
`canvas.bas` the module `canvas`). Module names win over the built-in classes, so `Dim h As
Http` would mean the module. Rename the file, for example to `webfetch.bas`. The built-in
classes are `Http`, `Canvas`, `Audio` and `Engine3D`, and the classes of any extensions the
program uses. A program `http.bas` that starts with `Dim h As Http` gives

```text
http.bas:1:10: error: the module 'http' hides the built-in class Http: rename the module
```

(A module named after `Collection`, the other built-in class, gives **duplicate module or class
name 'collection'** instead.)

### Warnings

**local 'x' hides constant 'X' (line n)**: a local variable has the same name as a constant
(names are not case-sensitive), so the constant cannot be used in that procedure.

**'x' hides the Public 'x' of module M here**: a module-level variable with the same name as a
`Public` one in another module; in this module the name means the local one.

**module-level statements in 'M' never run (only the startup module's do): move them into a
Sub**: statements outside any procedure in a module that is not the startup module (also in a
file added with `#Include` or `Uses=`). Only declarations belong there; put the statements in
a Sub and call it ([Program structure](04-data.md#the-shape-of-a-program)).

See also: [Errors and error handling](08-errors.md), [Built-in functions](appendix-b-functions.md).
