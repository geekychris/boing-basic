# Control flow

This chapter covers the statements that decide what runs next: `If` and `Select Case` for
decisions, `For`, `Do`, and `While` for loops, `Exit` to leave a loop or procedure early,
`GoTo`, `GoSub` and `On ... GoTo` for jumps, and `End` and `Stop` to finish a program. Error
handling with `On Error` is in [chapter 8](08-errors.md).

## Conditions

A condition is any expression that gives a Boolean, such as `x > 5`, `name = "Ann"` or
`Not done And count < 10`. A number also works as a condition: 0 is false and anything else
is true. The operators are in [chapter 7](07-expressions.md).

`And` and `Or` always work out both sides: there is no short-circuit. In
`If i <= UBound(a) And a(i) > 0 Then`, `a(i)` is read even when `i` is past the end, which is
error 9. Use two `If` statements instead, or an `ElseIf` chain.

## If

### Single-line If

The whole statement is on one line. The statements after `Then` run when the condition is
true, and those after `Else` (if there is one) when it is false. Several statements are
separated by colons:

*Listing 6.1* (`examples/book/ch06-control-flow/listing-06-01.bas`)

<!-- run -->
```basic
Dim score As Integer
score = 75
If score >= 50 Then Print "Pass"
If score >= 90 Then Print "Excellent" Else Print "Score:"; score
If score > 70 Then Print "Well done";: Print "!" Else Print "Keep going": Print "..."
```

```output
Pass
Score: 75 
Well done!
```

Everything up to the end of the line belongs to the `If`, including statements after a
colon. A single-line `If` can contain another one: `If a Then If b Then Print "both"`.

A line number after `Then` or `Else` is a `GoTo` to it: `If n < 3 Then 10`.

### Block If

When the `If` line ends after `Then`, the statements on the following lines, up to
`ElseIf`, `Else` or `End If`, form the block. `ElseIf` tests another condition when the ones
before were false, and there can be any number of them. `Else` catches everything that is
left:

*Listing 6.2* (`examples/book/ch06-control-flow/listing-06-02.bas`)

<!-- run -->
```basic
Sub Grade(ByVal score As Integer)
    If score >= 90 Then
        Print score; "A"
    ElseIf score >= 75 Then
        Print score; "B"
    ElseIf score >= 50 Then
        Print score; "C"
    Else
        Print score; "fail"
    End If
End Sub

Grade 95: Grade 80: Grade 60: Grade 10
```

```output
 95 A
 80 B
 60 C
 10 fail
```

Only the first branch whose condition is true runs.

`ElseIf` is one word. Written as two words, `Else If` is an `Else` followed by a new block
`If` inside it, and that inner `If` needs an `End If` of its own:

*Listing 6.3* (`examples/book/ch06-control-flow/listing-06-03.bas`)

<!-- run -->
```basic
Sub Sign(ByVal n As Integer)
    If n > 0 Then
        Print n; "positive"
    Else If n < 0 Then
        Print n; "negative"
    Else
        Print n; "zero"
    End If
    End If
End Sub

Sign 5: Sign -3: Sign 0
```

```output
 5 positive
-3 negative
 0 zero
```

The first `End If` closes the inner `If`, the second the outer one. If you leave one out,
`boing check` reports "expected 'End If', found end of file". Write `ElseIf` and you need only
one.

## Select Case

`Select Case` compares one value against a list of cases and runs the first case that
matches. The value is worked out once:

*Listing 6.4* (`examples/book/ch06-control-flow/listing-06-04.bas`)

<!-- run -->
```basic
Sub Describe(ByVal n As Integer)
    Select Case n
        Case 0
            Print n; "zero"
        Case 1, 2, 3
            Print n; "small"
        Case 4 To 9, 11
            Print n; "medium"
        Case Is >= 100
            Print n; "huge"
        Case Is < 0
            Print n; "negative"
        Case Else
            Print n; "large"
    End Select
End Sub

Describe 0: Describe 2: Describe 7: Describe 11: Describe 10: Describe 500: Describe -3
```

```output
 0 zero
 2 small
 7 medium
 11 medium
 10 large
 500 huge
-3 negative
```

Each `Case` has one or more tests, separated by commas, and matches if any of them does:

| Test | Matches when the value |
|---|---|
| `expr` | equals `expr` |
| `low To high` | is between `low` and `high`, inclusive |
| `Is op expr` | compares true with `op` (`=`, `<>`, `<`, `<=`, `>`, `>=`) |
| `op expr` | the same; `Is` can be left out |

`Case Else`, if present, must be the last case: it runs when no other case matches. When no
case matches and there is no `Case Else`, nothing runs. A case's statements can follow it on
the same line after a colon (`Case 1: Print "one"`).

Strings work too, compared as for `=` and `<` (so `Option Compare Text` makes the cases
ignore case). `Select Case True` with a condition in each `Case` is a tidy way to write a
chain of tests:

*Listing 6.5* (`examples/book/ch06-control-flow/listing-06-05.bas`)

<!-- run -->
```basic
Dim fruit As String, t As Double
fruit = "mango"
Select Case fruit
    Case "apple", "pear": Print "orchard fruit"
    Case "kiwi" To "orange": Print "between kiwi and orange"
    Case Else: Print "something else"
End Select
t = 21.5
Select Case True
    Case t < 0: Print "freezing"
    Case t < 15: Print "cold"
    Case t < 25: Print "mild"
    Case Else: Print "hot"
End Select
```

```output
between kiwi and orange
mild
```

The value can be a number, a String, a Boolean, a Date or a Variant; not an array or a
user-defined type.

## For ... Next

`For` repeats a block with a counter that goes from a start value to an end value:

```text
For counter = start To end [Step step]
    statements
Next [counter]
```

*Listing 6.6* (`examples/book/ch06-control-flow/listing-06-06.bas`)

<!-- run -->
```basic
Dim i As Integer, x As Double
For i = 1 To 5
    Print i;
Next i
Print
For i = 10 To 1 Step -3
    Print i;
Next
Print
For x = 0 To 1 Step 0.25
    Print x;
Next
Print
Print "after the loop i is"; i
```

```output
 1  2  3  4  5 
 10  7  4  1 
 0  .25  .5  .75  1 
after the loop i is-2 
```

How the loop works:

- `start`, `end` and `step` are worked out once, before the loop starts. Changing a variable
  used in them inside the loop does not change the number of times round.
- `Step` defaults to 1. With a positive step the loop runs while the counter is at most
  `end`; with a negative step, while it is at least `end`. If the counter already starts
  past the end, the body never runs.
- After the loop, the counter holds the first value past the end (6 for `For i = 1 To 5`).
  So an Integer counter cannot run up to 32767: the step past it is error 6, "Overflow".
- The counter must be a numeric variable (any number type or a Variant, but not a Boolean).
  You can change it inside the loop, which changes where the loop goes next.
- A step of 0 never reaches the end, so the loop runs until something leaves it.

The name after `Next` is optional, but if you give it, it must match the `For`. One `Next` can
close several loops: `Next j, i` closes the inner loop `j` and then the outer loop `i`.

*Listing 6.7* (`examples/book/ch06-control-flow/listing-06-07.bas`)

<!-- run -->
```basic
Dim row As Integer, col As Integer
For row = 1 To 3
    For col = 1 To 4
        Print row * col;
    Next col
    Print
Next row
For row = 1 To 2
    For col = 1 To 2
        Print row * 10 + col;
Next col, row
Print
```

```output
 1  2  3  4 
 2  4  6  8 
 3  6  9  12 
 11  12  21  22 
```

## For Each ... Next

`For Each` takes each element of an array, a `Collection` or an object in turn. The loop
variable must be a Variant (or an object variable, for a collection of objects, or a simple
type matching the array):

*Listing 6.8* (`examples/book/ch06-control-flow/listing-06-08.bas`)

<!-- run -->
```basic
Dim colours As Variant, c As Variant
colours = Array("red", "green", "blue")
For Each c In colours
    Print c
Next
```

```output
red
green
blue
```

`For Each` with collections and objects is described in [chapter 11](11-classes.md). It does
not work on an array of user-defined types.

## Do ... Loop

`Do ... Loop` repeats a block while a condition is true (`While`) or until it becomes true
(`Until`). The test can be at the top, where it is checked before each pass, so the block may
not run at all, or at the bottom, where it is checked after each pass, so the block runs at
least once. Without any test, the loop runs until `Exit Do` (or `GoTo`, `Exit Sub`, `End`)
leaves it.

| Form | Runs the block |
|---|---|
| `Do While cond ... Loop` | while `cond` is true, testing first |
| `Do Until cond ... Loop` | until `cond` is true, testing first |
| `Do ... Loop While cond` | at least once, then while `cond` is true |
| `Do ... Loop Until cond` | at least once, then until `cond` is true |
| `Do ... Loop` | for ever, until something leaves it |

*Listing 6.9* (`examples/book/ch06-control-flow/listing-06-09.bas`)

<!-- run -->
```basic
Dim n As Integer
n = 1
Do While n < 100
    n = n * 2
Loop
Print "While:"; n
n = 1
Do Until n >= 100
    n = n * 3
Loop
Print "Until:"; n
n = 500
Do
    n = n + 1
Loop While n < 10
Print "Loop While:"; n
n = 0
Do
    n = n + 1
    If n * n > 50 Then Exit Do
Loop
Print "Exit Do:"; n
```

```output
While: 128 
Until: 243 
Loop While: 501 
Exit Do: 8 
```

## While ... Wend

`While cond ... Wend` is the same as `Do While cond ... Loop`. `Exit Do` also leaves a
`While` loop.

*Listing 6.10* (`examples/book/ch06-control-flow/listing-06-10.bas`)

<!-- run -->
```basic
Dim count As Integer
While count < 3
    count = count + 1
    Print "pass"; count
Wend
```

```output
pass 1 
pass 2 
pass 3 
```

## Leaving early: Exit

| Statement | Leaves |
|---|---|
| `Exit For` | the innermost `For` or `For Each` loop |
| `Exit Do` | the innermost `Do` or `While` loop |
| `Exit Sub` | the current Sub |
| `Exit Function` | the current Function, returning the value assigned so far |
| `Exit Property` | the current Property procedure |

Execution goes on after the end of the loop, or back to the caller. Each must be inside the
kind of loop or procedure it names; otherwise it is a compile error. There is no statement
that skips to the next pass of a loop: put the rest of the body in an `If`, or jump to a
label just before `Next`.

*Listing 6.11* (`examples/book/ch06-control-flow/listing-06-11.bas`)

<!-- run -->
```basic
Function FindFirst(ByVal text As String, ByVal ch As String) As Long
    Dim i As Long
    For i = 1 To Len(text)
        If Mid$(text, i, 1) = ch Then
            FindFirst = i
            Exit Function
        End If
    Next
    FindFirst = -1
End Function

Print FindFirst("Boing BASIC", "B"); FindFirst("Boing BASIC", "S"); FindFirst("Boing", "z")
```

```output
 1  9 -1 
```

## Labels and GoTo

`GoTo` jumps to a label or a line number in the same procedure (or, at module level, among the
module-level statements). A label is a name followed by a colon at the start of a line, and a
line number is a number at the start of a line ([chapter 4](04-data.md#labels-and-line-numbers)).
You cannot jump into another procedure.

*Listing 6.12* (`examples/book/ch06-control-flow/listing-06-12.bas`)

<!-- run -->
```basic
Dim i As Integer
For i = 1 To 5
    If i = 3 Then GoTo skip
    Print i;
skip:
Next
Print
i = 0
again:
i = i + 1
If i < 3 Then GoTo again
Print "i ="; i
```

```output
 1  2  4  5 
i = 3 
```

Structured statements (`If`, loops, `Exit`) make programs easier to follow, so keep `GoTo` for
the few places where it is clearly simpler, such as error handling.

## GoSub and Return

`GoSub label` jumps to a label in the same procedure and remembers where it came from;
`Return` goes back to the statement after the `GoSub`. A `Return` without a `GoSub` is error 3,
"Return without GoSub". The code reached by `GoSub` is usually placed after an `Exit Sub` so
that it does not run by itself:

*Listing 6.13* (`examples/book/ch06-control-flow/listing-06-13.bas`)

<!-- run -->
```basic
Sub Squares()
    Dim v As Integer
    v = 4
    GoSub ShowSquare
    v = 5
    GoSub ShowSquare
    Exit Sub
ShowSquare:
    Print v; "squared is"; v * v
    Return
End Sub

Squares
```

```output
 4 squared is 16 
 5 squared is 25 
```

A Sub or Function with parameters is nearly always a better choice than `GoSub`.

## On ... GoTo and On ... GoSub

`On n GoTo label1, label2, ...` jumps to the first label when `n` is 1, the second when it is
2, and so on. If `n` is 0 or more than the number of labels, execution goes on with the next
statement. A negative `n`, or one above 255, is error 5. `On n GoSub` works the same way, with
a `Return` coming back after the `On` statement.

*Listing 6.14* (`examples/book/ch06-control-flow/listing-06-14.bas`)

<!-- run -->
```basic
Sub Pick(ByVal n As Integer)
    On n GoTo one, two
    Print n; "no match"
    Exit Sub
one:
    Print n; "one"
    Exit Sub
two:
    Print n; "two"
End Sub

Pick 1: Pick 2: Pick 3: Pick 0
```

```output
 1 one
 2 two
 3 no match
 0 no match
```

`On Error GoTo` is a different statement, for error handling ([chapter 8](08-errors.md)).

## End and Stop

`End` ends the program at once, wherever it is. Open files are closed and windows are shut,
but no more of your code runs. `Stop` prints `Stop` and then ends the program in the same way.

*Listing 6.15* (`examples/book/ch06-control-flow/listing-06-15.bas`)

<!-- run -->
```basic
Dim n As Integer
For n = 1 To 10
    If n = 3 Then End
    Print n
Next
Print "not reached"
```

```output
 1 
 2 
```

A program also ends normally after the last module-level statement, or when `Sub Main`
returns. A program with windows keeps running while a form is open ([chapter 12](12-forms.md)).

## Summary

- `If ... Then ... Else` on one line, or as a block with `ElseIf`, `Else` and `End If`.
- `Select Case` matches values, lists, `To` ranges and `Is` comparisons; `Case Else` catches
  the rest.
- `For ... Next` with `Step`, `For Each` for arrays and collections, `Do ... Loop` with
  `While` or `Until` at either end, and `While ... Wend`.
- `Exit For`, `Exit Do`, `Exit Sub`, `Exit Function` and `Exit Property` leave early.
- `GoTo`, `GoSub ... Return` and `On n GoTo/GoSub` jump to labels in the same procedure.
- `And` and `Or` do not short-circuit.

See also: [Program structure and data](04-data.md), [Procedures and modules](05-procedures.md),
[Expressions, operators and conversions](07-expressions.md),
[Errors and error handling](08-errors.md).
