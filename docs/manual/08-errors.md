# Errors and error handling

Things go wrong: a file is missing, a number is too big for its variable, a user types letters
where you wanted digits. This chapter covers run-time errors (what happens when one is not
handled, and how to catch it with `On Error`), the `Err` object, raising your own errors, how
errors travel through nested procedures, what Ctrl-C does to a running program, and the
compile-time errors that `boing check` reports before a program runs at all.

## Two kinds of error

A **compile-time error** is a mistake in the program text: a misspelt keyword, a missing
`End If`, a variable that was never declared under `Option Explicit`. Boing BASIC finds these
before the program starts, whether you use `boing check`, `boing run` or `boing build`, and the
program does not run until they are fixed. See [Compile-time errors](#compile-time-errors)
below.

A **run-time error** happens while the program runs: dividing by zero, an array index outside
the array, opening a file that does not exist. Each run-time error has a number and a message,
for example 11 "Division by zero" or 53 "File not found". The full list is in
[Appendix C](appendix-c-errors.md).

## When an error is not handled

If nothing in the program handles a run-time error, the program stops at once. It prints the
source file, the line, the error number and the message on the error output, and ends with the
return code 20 (an AmigaDOS `FAIL`):

*Listing 8.1* (`examples/book/ch08-errors/listing-08-01.bas`)

```basic
Sub Main()
    Dim scores(3) As Integer
    scores(5) = 10
    Print "never printed"
End Sub
```

```text
scores.bas:3: runtime error 9: Subscript out of range
```

A script can test the return code (`If FAIL` in an AmigaDOS script). `boing run
--error-file F prog.bas` also writes the message into the file `F`, where an editor or IDE can
read where the program stopped. Setting the environment variable
`BOING_ERROR_FILE` to a file name does the same for a native (built) program.

Before it ends, the runtime closes the program's files and windows, stops its sounds and timers
and frees the memory it allocated, so an error never leaves a window open on the Workbench.

## Catching an error: On Error GoTo

`On Error GoTo label` turns on an **error handler** for the rest of the procedure. When a
run-time error happens after it, the program jumps to the label instead of stopping:

*Listing 8.2* (`examples/book/ch08-errors/listing-08-02.bas`)

<!-- run -->
```basic
Sub ShowRatio(ByVal a As Long, ByVal b As Long)
    Dim q As Long
    On Error GoTo failed
    q = a \ b
    Print a; "/"; b; "="; q
    Exit Sub
failed:
    Print "cannot divide"; a; "by"; b; "- error"; Err.Number; Err.Description
End Sub

ShowRatio 10, 3
ShowRatio 7, 0
Print "the program goes on"
```

```output
 10 / 3 = 3 
cannot divide 7 by 0 - error 11 Division by zero
the program goes on
```

Three things to notice:

- The label (`failed:`) is an ordinary line label inside the same procedure. A line number
  (`On Error GoTo 100`) works too.
- `Exit Sub` (or `Exit Function`, `Exit Property`) stands just before the handler, so that a
  run without an error does not fall into it.
- Inside the handler, the `Err` object says what went wrong (see [The Err
  object](#the-err-object)).

When the handler reaches the end of the procedure (or an `Exit Sub`), the procedure returns
normally and `Err` is cleared. To go back into the code instead, use `Resume`.

## Resume: going back after an error

A handler can end with one of three forms of `Resume`:

| Statement | Where the program continues |
|---|---|
| `Resume` | at the statement that caused the error, which runs again |
| `Resume Next` | at the statement after the one that caused the error |
| `Resume label` | at a label (or line number) in the same procedure |

Each of them clears `Err`. `Resume` is for errors the handler can repair: here the handler
fixes the divisor and tries again.

*Listing 8.3* (`examples/book/ch08-errors/listing-08-03.bas`)

<!-- run -->
```basic
Sub Retry()
    Dim divisor As Integer, result As Integer
    On Error GoTo fix
    result = 100 \ divisor
    Print "result"; result; "with divisor"; divisor
    Exit Sub
fix:
    Print "error"; Err.Number; "- trying a divisor of 4"
    divisor = 4
    Resume
End Sub

Retry
```

```output
error 11 - trying a divisor of 4
result 25 with divisor 4 
```

`Resume Next` skips the statement that failed:

*Listing 8.4* (`examples/book/ch08-errors/listing-08-04.bas`)

<!-- run -->
```basic
Sub LoadAll()
    On Error GoTo skip
    Print "step 1"
    Err.Raise 53
    Print "step 3"
    Exit Sub
skip:
    Print "step 2 failed:"; Err.Number
    Resume Next
End Sub

LoadAll
```

```output
step 1
step 2 failed: 53 
step 3
```

`Resume label` continues somewhere else, typically at a common exit point:

*Listing 8.5* (`examples/book/ch08-errors/listing-08-05.bas`)

<!-- run -->
```basic
Function ParseAge(ByVal text As String) As Integer
    On Error GoTo bad
    ParseAge = CInt(text)
done:
    Exit Function
bad:
    Print "'"; text; "' is not a number"
    ParseAge = -1
    Resume done
End Function

Print ParseAge("42")
Print ParseAge("forty")
```

```output
 42 
'forty' is not a number
-1 
```

`Resume` when there is no error to resume from is itself an error (20, "Resume without
error"). This happens when a procedure falls into its handler without an error, which is why
the `Exit Sub` before the handler matters.

## On Error Resume Next

`On Error Resume Next` tells Boing BASIC to ignore run-time errors: a statement that fails is
skipped and the program carries on with the next one. You then look at `Err.Number` yourself
straight after the statements that might fail. It is handy for a short "try this" sequence:

*Listing 8.6* (`examples/book/ch08-errors/listing-08-06.bas`)

<!-- run -->
```basic
Dim n As Integer, v As Variant
On Error Resume Next

n = 40000
If Err.Number <> 0 Then Print "n:"; Err.Number; Err.Description
Err.Clear

v = Array(1, 2, 3)
Print v(7)
If Err.Number <> 0 Then Print "v:"; Err.Number; Err.Description
Err.Clear

Print "n is still"; n
```

```output
n: 6 Overflow
v: 9 Subscript out of range
n is still 0 
```

Clear `Err` with `Err.Clear` after you have dealt with an error, or the next test still sees the
old number. Do not leave `On Error Resume Next` switched on for a long stretch of code: it hides
real mistakes.

## On Error GoTo 0

`On Error GoTo 0` switches the current procedure's handler off again. Errors after it go to a
caller's handler, or stop the program if there is none:

*Listing 8.7* (`examples/book/ch08-errors/listing-08-07.bas`)

<!-- run -->
```basic
Sub Main()
    On Error Resume Next
    Kill "no-such-file.tmp"          ' fine if it is not there
    Print "after Kill:"; Err.Number
    Err.Clear
    On Error GoTo 0
    Print "errors stop the program again from here"
End Sub
```

```output
after Kill: 53 
errors stop the program again from here
```

Each procedure has its own handler. `On Error` in one procedure does not change the handler of
the procedure that called it, and when a procedure returns, its handler goes with it.

## On Error GoTo -1

While a handler is running, the procedure is "handling an error": a second error in it is not
caught by any `On Error` of that procedure, even a new `On Error GoTo` written inside the
handler, and goes to the caller instead. `Resume` ends that state, and so does leaving the
procedure.

`On Error GoTo -1` ends it without leaving the handler: it clears `Err` and makes the
procedure's handler catch errors again. Without it, the second `Err.Raise` below would stop the
program with error 9:

*Listing 8.8* (`examples/book/ch08-errors/listing-08-08.bas`)

<!-- run -->
```basic
Sub Main()
    On Error GoTo first
    Err.Raise 5
    Exit Sub
first:
    Print "first"; Err.Number
    On Error GoTo -1
    Print "after -1:"; Err.Number
    On Error GoTo second
    Err.Raise 9
    Exit Sub
second:
    Print "second"; Err.Number
End Sub
```

```output
first 5 
after -1: 0 
second 9 
```

The handler stays switched on after `On Error GoTo -1`, so a handler can also jump back into
the code with `GoTo` and catch the next error itself:

*Listing 8.9* (`examples/book/ch08-errors/listing-08-09.bas`)

<!-- run -->
```basic
Sub Main()
    Dim tries As Integer
    On Error GoTo h
again:
    tries = tries + 1
    Err.Raise 5
    Exit Sub
h:
    Print "try"; tries; Err.Number
    On Error GoTo -1
    If tries < 3 Then GoTo again
End Sub
```

```output
try 1  5 
try 2  5 
try 3  5 
```

Outside a handler, `On Error GoTo -1` only clears `Err`; the handler that is switched on stays
as it is.

## The Err object

`Err` holds the details of the most recent run-time error. Its members:

| Member | Type | What it is |
|---|---|---|
| `Err.Number` | Long | the error number; 0 when there is no error. `Err` alone means `Err.Number`. You can assign it |
| `Err.Description` | String | the message, e.g. "Division by zero". You can assign it |
| `Err.Source` | String | where the error came from: what `Err.Raise` gave as its source, otherwise empty. You can assign it |
| `Err.Raise number [, source [, description]]` | method | raises an error (see below) |
| `Err.Clear` | method | sets `Number` to 0 and empties `Description` and `Source` |
| `Err.LastDllError` | Long | always 0 (accepted so that existing code compiles; OS errors from `Declare` calls are not recorded here) |
| `Err.HelpFile`, `Err.HelpContext` | String, Long | always `""` and 0 (accepted, not used) |

`Err` is cleared by `Err.Clear`, by any form of `Resume`, by `On Error GoTo` / `On Error Resume
Next` (including `On Error GoTo -1`) and by leaving a procedure through `Exit Sub`, `Exit Function` or `Exit Property` from
its handler.

Two more built-ins go with it:

- `Erl` gives the line, counted in the source file, where the last error happened (0 if there
  is none). It is the real line in the file, whether or not the line has a line number.
- `Error(n)` (also `Error$(n)`) gives the standard message of error number `n`; with no
  argument it gives the current `Err.Description`.

*Listing 8.10* (`examples/book/ch08-errors/listing-08-10.bas`)

<!-- run -->
```basic
On Error Resume Next
Dim x As Integer
x = 32767 + 1
Print Err; Erl; Err.Description
Print Error(53); " / "; Error$(62)
Print Error(30000)
```

```output
 6  3 Overflow
File not found / Input past end of file
Application-defined or object-defined error
```

An error number without a standard message gives "Application-defined or object-defined
error".

## Raising your own errors

Your own procedures can report failures in the same way as the built-ins, so that callers
handle them with `On Error`. `Err.Raise number [, source [, description]]` raises error
`number`; the optional source and description fill in `Err.Source` and `Err.Description` (a
missing description gives the standard message for the number):

*Listing 8.11* (`examples/book/ch08-errors/listing-08-11.bas`)

<!-- run -->
```basic
Const ERR_EMPTY_NAME = vbObjectError + 1

Sub SetName(ByVal s As String)
    If Len(s) = 0 Then Err.Raise ERR_EMPTY_NAME, "SetName", "the name must not be empty"
    Print "name set to "; s
End Sub

Sub Main()
    On Error GoTo h
    SetName "Ada"
    SetName ""
    Exit Sub
h:
    Print "error"; Err.Number - vbObjectError; "from "; Err.Source; ": "; Err.Description
End Sub
```

```output
name set to Ada
error 1 from SetName: the name must not be empty
```

Choose your own numbers so they do not clash with the built-in ones: either add them to the
constant `vbObjectError` (-2147221504), as above, or use numbers from 1000 to 65535.

The `Error n` statement is an older, shorter way to raise error `n` with its standard message:

*Listing 8.12* (`examples/book/ch08-errors/listing-08-12.bas`)

<!-- run -->
```basic
On Error Resume Next
Error 62
Print Err.Number; Err.Description
```

```output
 62 Input past end of file
```

## Errors in nested procedures

When an error happens in a procedure that has no handler of its own, Boing BASIC looks at the
procedure that called it, then at that one's caller, and so on, and jumps to the first handler
it finds. The procedures in between are left at once, as if they had all returned:

*Listing 8.13* (`examples/book/ch08-errors/listing-08-13.bas`)

<!-- run -->
```basic
Sub Level3()
    Print "level 3 starts"
    Err.Raise 1001, "Level3", "deep trouble"
    Print "level 3 ends"                  ' never runs
End Sub

Sub Level2()
    Level3
    Print "level 2 ends"                  ' never runs
End Sub

Sub Level1()
    On Error GoTo h
    Level2
    Print "level 1 ends"
    Exit Sub
h:
    Print "level 1 caught"; Err.Number; Err.Source; ": "; Err.Description
End Sub

Level1
```

```output
level 3 starts
level 1 caught 1001 Level3: deep trouble
```

Some rules follow from this:

- A handler that catches an error from a called procedure can still use `Resume Next`: the
  program continues after the call in the handler's own procedure.
- An error that happens **inside a handler** (while the handler is running, before a `Resume`)
  is not caught by that same handler. It goes on to the next handler up, with its own number
  and description, whether it is an `Err.Raise` or a failing statement. That is how a handler
  passes on an error it cannot deal with: it calls `Err.Raise` again, perhaps with a better
  description (see the listing below).
- The local variables of the procedures that are left are released properly: an object whose
  last reference goes away runs its `Class_Terminate`, and arrays and strings are freed.
- In a form program, each event procedure (`Command1_Click` and so on) is called by the
  runtime, not by your code, so an error in it that it does not handle itself ends the program.
  Give event procedures that can fail their own `On Error GoTo` handler.

The program stops (with the message above) only when no procedure on the way up has a handler.

Here `LoadSettings` catches the "File not found" from `Open`, and passes it on to its caller
with a description that names the file. `Main`'s handler receives the number, source and
description that `LoadSettings` gave:

*Listing 8.14* (`examples/book/ch08-errors/listing-08-14.bas`)

<!-- run -->
```basic
Function LoadSettings(ByVal path As String) As String
    Dim f As Integer
    On Error GoTo failed
    f = FreeFile
    Open path For Input As #f
    Line Input #f, LoadSettings
    Close #f
    Exit Function
failed:
    Err.Raise Err.Number, "LoadSettings", "cannot read " & path & ": " & Err.Description
End Function

Sub Main()
    On Error GoTo h
    Print LoadSettings("no-such-settings.txt")
    Exit Sub
h:
    Print "Main caught"; Err.Number; " "; Err.Source
    Print Err.Description
End Sub
```

```output
Main caught 53  LoadSettings
cannot read no-such-settings.txt: File not found
```

The arguments of `Err.Raise` are worked out before the new error is raised, so the handler can
still use the old `Err.Number` and `Err.Description` in them.

## Ctrl-C: stopping a running program

Pressing Ctrl-C in the Shell window that runs a program (or sending the program a break signal,
for example with the AmigaDOS `Break` command) stops it. In
Boing BASIC a break is run-time error 18, "User interrupt occurred". It arrives at the next loop
turn or procedure call, so even a tight loop stops at once.

Without a handler, the program ends with `***Break` and the line it was on, and the return code
20:

```text
counter.bas:5: ***Break
```

Because a break is an ordinary error, a handler can catch it. This matters when the program has
opened something the runtime does not know about, for example a window or memory obtained
through `Declare` calls to the AmigaOS libraries (see [AmigaOS](17-amigaos.md)): the handler can
close it before the program ends.

*Listing 8.15* (`examples/book/ch08-errors/listing-08-15.bas`)

```basic
Sub Main()
    Dim counter As Long
    On Error GoTo cleanup
    Print "running: press Ctrl-C to stop"
    Do
        counter = counter + 1
    Loop
cleanup:
    If Err.Number = 18 Then Print "stopped by the user after"; counter; "turns"
    ' close windows, free memory, delete temporary files here
End Sub
```

`On Error Resume Next` does **not** swallow a break: error 18 skips such procedures and goes to
an `On Error GoTo` handler further up, or ends the program. A loop that runs under `On Error
Resume Next` can therefore still be stopped with Ctrl-C.

`Sleep` and `DoEvents` look for Ctrl-C straight away, so a program that waits in them stops at
once too. Whether or not your handler runs, the runtime's own clean-up (forms, sounds, timers,
files) always happens.

## Compile-time errors

`boing check prog.bas` (or `prog.bbp` for a project) checks a program without running it.
It prints one line per problem, in the form

```text
file:line:column: error: message
```

and nothing at all when the program is fine. The return code is 0 when there are no errors, and
non-zero when there is at least one, so a script or an editor can test it. `boing run` and
`boing build` check the program in the same way first and print the same messages; they do not
run or build a program that has errors.

Take this program, which has three mistakes:

<!-- error: variable 'totl' is not defined -->
```basic
Option Explicit
Dim total As Long, i As Integer
For i = 1 To 10
    totl = total + i
Next
Print Lenn(total)
Prnt total
```

`boing check` reports each mistake with its position (line 4, column 5 is where `totl`
starts):

```text
sums.bas:4:5: error: variable 'totl' is not defined
sums.bas:6:7: error: Sub, Function or array 'Lenn' is not defined
sums.bas:7:1: error: Sub, Function or array 'Prnt' is not defined
```

The checking happens in two stages. First the program text is read (**parsed**); a mistake in
the shape of a statement, such as a missing bracket or a missing `End If`, stops the check at
that point, because the rest cannot be understood reliably:

<!-- error: expected 'End If', found end of file -->
```basic
Dim n As Integer
n = 5
If n > 3 Then
    Print "big"
```

```text
big.bas:5:1: error: expected 'End If', found end of file
```

Once the text is understood, every statement is **checked**: names, types, the number of
arguments, and so on. This stage reports all the problems it finds, not just the first. Some
typical messages:

<!-- error: ByRef argument type mismatch -->
```basic
Sub Twice(n As Long)
    n = n * 2
End Sub

Dim count As Integer
Dim name As String
Twice count
count = Left("abc")
Set name = Nothing
Print name.Length
```

```text
types.bas:7:7: error: ByRef argument type mismatch: Integer variable passed for Long parameter 'n'
types.bas:8:9: error: wrong number of arguments to 'Left'
types.bas:9:1: error: Set needs an object variable ('name' is String)
types.bas:10:12: error: invalid qualifier: String has no members
```

The first message says that `Twice` wants a Long variable it can change (parameters are `ByRef`
unless you say `ByVal`, see [Procedures](05-procedures.md)), and `count` is an Integer. Pass
`CLng(count)` (a copy), declare `count As Long`, or make the parameter `ByVal`.

`boing check` also prints **warnings**: things that are allowed but probably not what you
meant, such as a local variable with the same name as a constant. A warning has the word
`warning` instead of `error`, and on its own it does not make the check fail:

```text
calc.bas:4:9: warning: local 'limit' hides constant 'Limit' (line 2)
```

[Appendix C](appendix-c-errors.md) lists the most common compile-time messages with examples.

## Summary

- An unhandled run-time error prints `file:line: runtime error n: message` and ends the
  program with return code 20.
- `On Error GoTo label` catches errors in the rest of the procedure (and in the procedures it
  calls); end the main code with `Exit Sub` before the label.
- `Resume`, `Resume Next` and `Resume label` go back into the code; leaving the handler at the
  end of the procedure returns normally.
- `On Error Resume Next` skips failing statements; test `Err.Number` and use `Err.Clear`.
  `On Error GoTo 0` turns the handler off; `On Error GoTo -1` ends the handling of an error
  inside a handler, so that the next error is caught again.
- An error raised inside a handler goes to the caller's handler with its number and
  description.
- `Err.Number`, `Err.Description`, `Err.Source`, `Err.Raise`, `Err.Clear`, `Erl` and `Error(n)`
  tell you about errors and let you raise your own.
- Ctrl-C is error 18: catch it to clean up, or let it end the program with `***Break`.
- `boing check` reports compile-time errors as `file:line:column: error: message`.

See also: [Procedures](05-procedures.md), [Files and the system](10-files.md),
[Run-time error numbers](appendix-c-errors.md).
