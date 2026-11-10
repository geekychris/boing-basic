# Procedures and modules

This chapter shows how to split a program into procedures: `Sub` procedures that do a job,
`Function` procedures that return a value, and `Property` procedures that look like
variables. It covers parameters (`ByVal`, `ByRef`, `Optional`, `ParamArray`, named
arguments), recursion, `Static` variables, and how names are shared between the modules of a
project. Class modules, which use the same procedures, are in [chapter 11](11-classes.md).

## Sub procedures

A `Sub` is a named block of statements. You call it by its name, with any arguments after the
name, separated by commas:

*Listing 5.1* (`examples/book/ch05-procedures/listing-05-01.bas`)

<!-- run -->
```basic
Sub Greet(ByVal who As String, ByVal times As Integer)
    Dim i As Integer
    For i = 1 To times
        Print "Hello, "; who
    Next
End Sub

Greet "Ann", 2
Call Greet("Bob", 1)
```

```output
Hello, Ann
Hello, Ann
Hello, Bob
```

There are two ways to call a Sub:

- `Greet "Ann", 2`: the name, then the arguments without parentheses.
- `Call Greet("Bob", 1)`: the `Call` keyword, with the arguments in parentheses.

`Greet("Ann", 2)` without `Call` is a syntax error. A single argument in parentheses,
`Greet ("Ann")`, is allowed, but it means something different: the parentheses make the
argument an expression, so it is passed as a copy (see [ByRef](#byval-and-byref) below).

`Exit Sub` leaves a Sub at once. `End Sub` ends its declaration.

## Function procedures

A `Function` returns a value. Inside the function, its own name acts as a variable that holds
the result: assign to it, and the value it has when the function ends is returned. Declare the
type of the result with `As` after the parameter list:

*Listing 5.2* (`examples/book/ch05-procedures/listing-05-02.bas`)

<!-- run -->
```basic
Function Average(ByVal a As Double, ByVal b As Double) As Double
    Average = (a + b) / 2
End Function

Function Sign(ByVal n As Long) As String
    Sign = "zero"
    If n > 0 Then Sign = "positive": Exit Function
    If n < 0 Then Sign = "negative"
End Function

Print Average(3, 4)
Print Sign(5); " "; Sign(-2); " "; Sign(0)
```

```output
 3.5 
positive negative zero
```

The result starts with the default value of its type (0, `""`, `Empty` and so on), so a
function that never assigns its name returns that default. `Exit Function` returns at once,
with whatever value has been assigned so far.

A function without `As` returns a Variant (or the type of its name's suffix, or of a
`DefType` range). A function can return any type, including an array (`As Long()`), a
user-defined type or an object; to return an object, assign the result with
`Set FunctionName = ...`.

*Listing 5.3* (`examples/book/ch05-procedures/listing-05-03.bas`)

<!-- run -->
```basic
Function Range(ByVal first As Long, ByVal last As Long) As Long()
    Dim r() As Long, i As Long
    ReDim r(first To last)
    For i = first To last
        r(i) = i
    Next
    Range = r
End Function

Dim nums() As Long
nums = Range(5, 9)
Print LBound(nums); UBound(nums); nums(7)
```

```output
 5  9  7 
```

You can call a Function as a statement, like a Sub, when you do not need its value
(`Average 1, 2`, or `Call Average(1, 2)`): the result is thrown away. Using a Sub where a
value is needed is a compile error.

## Parameters

### ByVal and ByRef

A parameter is passed either by value or by reference:

- **`ByVal`**: the procedure gets a copy of the argument. Changing the parameter does not
  change the caller's variable.
- **`ByRef`** (the default): the parameter is another name for the caller's variable.
  Changing the parameter changes the variable.

*Listing 5.4* (`examples/book/ch05-procedures/listing-05-04.bas`)

<!-- run -->
```basic
Sub AddOneRef(n As Long)          ' ByRef is the default
    n = n + 1
End Sub

Sub AddOneVal(ByVal n As Long)
    n = n + 1
End Sub

Sub Swap(a As Long, b As Long)
    Dim t As Long
    t = a: a = b: b = t
End Sub

Dim k As Long, x As Long, y As Long
k = 1
AddOneVal k: Print k
AddOneRef k: Print k
AddOneRef (k): Print k            ' (k) is an expression: a copy is passed
x = 1: y = 2
Swap x, y
Print x; y
```

```output
 1 
 2 
 2 
 2  1 
```

Only a variable, an array element or a field of a record can be passed by reference. When
the argument is anything else (a constant, an expression such as `k + 0`, or a variable in
parentheses), a copy is passed, and changes to the parameter are lost.

A variable passed `ByRef` must have exactly the parameter's type. Passing an Integer variable
to a `ByRef ... As Long` parameter is a compile error, "ByRef argument type mismatch". Convert
it explicitly to pass a copy (`AddOneRef CLng(i)`), or declare the parameter `ByVal`:

<!-- error: ByRef argument type mismatch -->
```basic
Sub AddOneRef(n As Long)
    n = n + 1
End Sub
Dim i As Integer
AddOneRef i
```

A typed variable passed to a `ByRef` Variant parameter is passed as a copy: the procedure
can change the parameter, but the caller's variable is not changed. Only a Variant variable
passed to a Variant parameter is shared.

Use `ByVal` for values a procedure only reads, and `ByRef` when it has to give results back
through its parameters. Arrays and user-defined types are always passed by reference;
declaring them `ByVal` is a compile error.

### Array parameters

Declare an array parameter with empty parentheses. The procedure can use `LBound` and
`UBound` to find the array's size, and can `ReDim` a dynamic array it is given:

*Listing 5.5* (`examples/book/ch05-procedures/listing-05-05.bas`)

<!-- run -->
```basic
Function Sum(values() As Long) As Long
    Dim i As Long
    For i = LBound(values) To UBound(values)
        Sum = Sum + values(i)
    Next
End Function

Sub Grow(values() As Long, ByVal extra As Long)
    ReDim Preserve values(UBound(values) + extra)
End Sub

Dim fixed(1 To 3) As Long, dyn() As Long
fixed(1) = 10: fixed(2) = 20: fixed(3) = 30
Print Sum(fixed)
ReDim dyn(1)
Grow dyn, 4
Print UBound(dyn)
```

```output
 60 
 5 
```

The argument must be an array variable of the same element type. A Variant parameter takes
any array, including one made by `Array()` or `Split()`.

### Optional parameters

`Optional` marks a parameter the caller can leave out. Give it a default value with `= value`
(a constant expression); without one, it gets its type's default. For an `Optional` Variant
without a default, `IsMissing(param)` tells you whether the caller passed it. Every
parameter after an `Optional` one must be `Optional` too.

*Listing 5.6* (`examples/book/ch05-procedures/listing-05-06.bas`)

<!-- run -->
```basic
Function Area(ByVal w As Double, Optional ByVal h As Double = -1) As Double
    If h < 0 Then h = w          ' a square if no height is given
    Area = w * h
End Function

Sub Report(ByVal title As String, Optional detail As Variant)
    If IsMissing(detail) Then
        Print title
    Else
        Print title; ": "; detail
    End If
End Sub

Print Area(3); Area(3, 4)
Report "Done"
Report "Done", "3 files"
```

```output
 9  12 
Done
Done: 3 files
```

`IsMissing` works only for Variant parameters. A typed `Optional` parameter that is left out
has its default value, and `IsMissing` gives `False` for it.

To leave out an argument in the middle, write nothing between the commas:
`Draw 10, , 30`.

### Named arguments

You can pass arguments by the parameter's name, with `:=`, in any order. This is clearest
with procedures that have several optional parameters:

*Listing 5.7* (`examples/book/ch05-procedures/listing-05-07.bas`)

<!-- run -->
```basic
Sub Box(Optional ByVal w As Long = 1, Optional ByVal h As Long = 1, Optional ByVal fill As String = "#")
    Dim r As Long
    For r = 1 To h
        Print String(w, fill)
    Next
End Sub

Box h:=2, w:=5
Box 3, fill:="*"
```

```output
#####
#####
***
```

Positional arguments come first, then named ones. Naming the same parameter twice, or a name
the procedure does not have, is a compile error. Named arguments cannot be used in late-bound
calls on `Object` variables ([chapter 11](11-classes.md)).

### ParamArray

A `ParamArray` parameter collects any number of arguments into a Variant array. It must be
the last parameter, and it is declared as a Variant array, `ParamArray name()` (or
`ParamArray name() As Variant`). With no arguments, the array is empty and its `UBound` is
-1.

*Listing 5.8* (`examples/book/ch05-procedures/listing-05-08.bas`)

<!-- run -->
```basic
Function Total(ParamArray nums() As Variant) As Double
    Dim x As Variant
    For Each x In nums
        Total = Total + x
    Next
End Function

Sub ShowAll(ByVal label As String, ParamArray items())
    Dim i As Long
    Print label; UBound(items) + 1; "item(s):";
    For i = 0 To UBound(items)
        Print " "; items(i);
    Next
    Print
End Sub

Print Total(1, 2, 3.5); Total()
ShowAll "Got", "a", 2, True
ShowAll "Got"
```

```output
 6.5  0 
Got 3 item(s): a  2  True
Got 0 item(s):
```

## Recursion

A procedure can call itself. Inside a Function, the function's name with arguments in
parentheses is a recursive call; without them it is the result variable:

*Listing 5.9* (`examples/book/ch05-procedures/listing-05-09.bas`)

<!-- run -->
```basic
Function Factorial(ByVal n As Long) As Double
    If n <= 1 Then
        Factorial = 1
    Else
        Factorial = n * Factorial(n - 1)
    End If
End Function

Sub Countdown(ByVal n As Integer)
    If n = 0 Then Print "Lift off!": Exit Sub
    Print n;
    Countdown n - 1
End Sub

Print Factorial(10); Factorial(20)
Countdown 5
```

```output
 3628800  2.43290200817664E+18 
 5  4  3  2  1 Lift off!
```

Each call has its own local variables. Recursion that never stops runs out of stack: error
28, "Out of stack space". A project can raise the stack size with the `Stack=` key in its
`.bbp` file ([chapter 2](02-shell.md)).

## Local variables and Static

Variables declared with `Dim` inside a procedure are local: only that procedure sees them,
and they are created afresh, with their default values, on each call. A local variable hides
a module variable of the same name.

`Static` instead of `Dim` declares a local variable that keeps its value from one call to the
next. `Static` in front of `Sub`, `Function` or `Property` makes every local variable of that
procedure static:

*Listing 5.10* (`examples/book/ch05-procedures/listing-05-10.bas`)

<!-- run -->
```basic
Dim level As Integer

Sub Show()
    Dim level As Integer          ' hides the module's level
    level = 99
    Print "inside"; level
End Sub

Function NextId() As Long
    Static lastId As Long
    lastId = lastId + 1
    NextId = lastId
End Function

Static Function RunningTotal(ByVal x As Long) As Long
    Dim sum As Long               ' static, because the whole Function is Static
    sum = sum + x
    RunningTotal = sum
End Function

level = 1
Show
Print "outside"; level
Print NextId(); NextId(); NextId()
Print RunningTotal(5); RunningTotal(10)
```

```output
inside 99 
outside 1 
 1  2  3 
 5  15 
```

A static variable is shared by all calls, including recursive ones, and it lasts until the
program ends.

## Property procedures

Property procedures let code use what looks like a variable while a procedure runs behind it.
They are used most in class modules ([chapter 11](11-classes.md)), but work in ordinary
modules too:

- `Property Get Name() As Type` runs when the property is read, and returns its value like a
  Function.
- `Property Let Name(ByVal v As Type)` runs when a value is assigned (`Name = value`). Its
  last parameter is the value.
- `Property Set Name(ByVal v As Object)` runs when an object is assigned
  (`Set Name = obj`).

*Listing 5.11* (`examples/book/ch05-procedures/listing-05-11.bas`)

<!-- run -->
```basic
Private mVolume As Integer

Property Get Volume() As Integer
    Volume = mVolume
End Property

Property Let Volume(ByVal v As Integer)
    If v < 0 Then v = 0
    If v > 64 Then v = 64          ' keep it in range
    mVolume = v
End Property

Property Get Cell(ByVal row As Long, ByVal col As Long) As Long
    Cell = row * 10 + col
End Property

Volume = 100
Print Volume
Volume = Volume - 70
Print Volume
Print Cell(2, 3)
```

```output
 64 
 0 
 23 
```

A property can take extra parameters, as `Cell` does; for a `Property Let` they come before
the value. A property with only a `Property Get` is read-only, and assigning to it is a
compile error. `Exit Property` leaves a property procedure early.

## Modules and scope

A project (`.bbp` file) lists the modules that make up the program, one per `Module=` line,
with class modules on `Class=` lines and forms on `Form=` lines. The first module is the
startup module ([chapter 4](04-data.md#the-shape-of-a-program)). Projects and their keys are
described in [chapter 2](02-shell.md). There is no `#Include` statement: to share code, add
its module to the project.

### What each module can see

| Declared at module level as | Visible in |
|---|---|
| `Dim x`, `Private x` | that module only |
| `Public x`, `Global x` | every module |
| `Sub`, `Function`, `Property` (no keyword, or `Public`) | every module |
| `Private Sub`, `Private Function`, `Private Property` | that module only |
| `Const` (no keyword, or `Private`) | that module only |
| `Public Const` | every module |
| `Type`, `Enum` (no keyword, or `Public`) | every module |
| `Private Type`, `Private Enum` | that module only |

`Public`, `Private` and `Global` are allowed only at module level; inside a procedure, use
`Dim`, `Static` and `Const`.

### Qualified names

To use a name from a particular module, write the module's name (its file name without
`.bas`) and a dot: `util.Twice(5)`, `util.Counter`. This is how you choose between two
modules that each have a public procedure of the same name. Without the module name, the
first module in the project's list that has the name is used, so qualify names that are
defined in more than one module.

A module-level declaration with the same name as another module's `Public` one hides it in
that module; `boing check` warns about it.

### An example project

This project has three modules. `util.bas` holds a public variable, a constant, an
enumeration, a function, a property and a private helper; `shapes.bas` holds a user-defined
type, a function that takes it, and a second `Twice`:

```ini
Name=Modules
Module=main.bas
Module=util.bas
Module=shapes.bas
```

`util.bas`:

*Listing 5.12* (`examples/book/ch05-procedures/modules/modules.bbp`)

<!-- project: examples/book/ch05-procedures/modules/modules.bbp -->
```basic
Option Explicit
Public Counter As Long
Private mSecret As String
Public Const VERSION_TEXT = "1.2"

Public Enum Color
    Red = 1
    Green
    Blue = 10
End Enum

Public Function Twice(ByVal x As Long) As Long
    Counter = Counter + 1
    Twice = x * 2
End Function

Public Property Get Secret() As String
    Secret = "[" & mSecret & "]"
End Property

Public Property Let Secret(ByVal v As String)
    mSecret = UCase$(v)
End Property

Private Function Hidden() As Long
    Hidden = 42
End Function

Public Function CallsHidden() As Long
    CallsHidden = Hidden()
End Function
```

`shapes.bas`:

*Listing 5.13* (`examples/book/ch05-procedures/modules/modules.bbp`)

<!-- project: examples/book/ch05-procedures/modules/modules.bbp -->
```basic
Public Type Box
    W As Long
    H As Long
End Type

Public Function Area(b As Box) As Long
    Area = b.W * b.H
End Function

Public Function Twice(ByVal x As Long) As Long
    Twice = x * 3   ' a different Twice: qualify to pick one
End Function
```

`main.bas`, the startup module:

*Listing 5.14* (`examples/book/ch05-procedures/modules/modules.bbp`)

<!-- project: examples/book/ch05-procedures/modules/modules.bbp -->
```basic
Option Explicit
Dim b As Box
b.W = 3: b.H = 4
Print Area(b)
Print util.Twice(5); shapes.Twice(5); Counter
Secret = "abc"
Print Secret
Print VERSION_TEXT; " "; Red; Green; Blue; Color.Blue
Dim c As Color
c = Green
Print c
Print CallsHidden()
```

Running the project prints:

```text
 12 
 10  15  1 
[ABC]
1.2  1  2  10  10 
 2 
 42
```

`main.bas` cannot call `Hidden` (it is private to `util.bas`), but it can call the public
`CallsHidden`, which can.

## Sub Main and the startup form

A program whose startup module has no module-level statements starts by running `Sub Main`.
A project for a program with windows usually names a form to open instead
(`Startup=Form MainForm` in the `.bbp` file); the form's events then drive the program.
Forms are covered in [chapter 12](12-forms.md).

*Listing 5.15* (`examples/book/ch05-procedures/listing-05-15.bas`)

<!-- run -->
```basic
Sub Main()
    Print "Starting"
    Setup
    Print "Done"
End Sub

Private Sub Setup()
    Print "Setting up"
End Sub
```

```output
Starting
Setting up
Done
```

## Summary

- `Sub` does a job; `Function` returns a value through its own name; `Property Get/Let/Set`
  look like variables.
- Call a Sub with `Name a, b` or `Call Name(a, b)`.
- Parameters are `ByRef` by default; a ByRef variable argument must match the type exactly.
- `Optional` (with defaults, and `IsMissing` for Variants), named arguments `name:=value` and
  `ParamArray` make flexible procedures.
- `Static` keeps local variables between calls.
- `Public` names are shared across a project's modules; qualify with `module.name` when two
  modules use the same name.

See also: [Program structure and data](04-data.md), [Control flow](06-control-flow.md),
[Errors and error handling](08-errors.md), [Classes and objects](11-classes.md).
