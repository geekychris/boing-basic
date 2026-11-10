# Exercise 3: Classes and events

In this exercise you write a small bank. Each account is an **object**: it keeps its own
owner, balance and overdraft limit, checks every change, and tells the rest of the program
when something happens by raising **events**. This is how the controls on a form work too,
so it is good preparation for the form exercises that follow.

**Goal:** a program that opens accounts, pays money in and out, refuses or warns about
overdrafts through events, and prints a statement.

**What you will learn:**

- a class module (`.cls`) and `New`, `Set`, `Nothing`
- `Class_Initialize` and `Class_Terminate`
- `Property Get` and `Property Let`, read-only properties, checking values with `Err.Raise`
- `Public Event`, `RaiseEvent`, and handling events with `WithEvents`
- a `Collection` of objects with keys, and `For Each` over it
- `Currency` for money, and `Format`

The solution is in `examples/book/ex03-classes/` (`Bank.bbp`), with the first step in
`examples/book/ex03-classes/first/`.

## Step 1: A first class

A class is a module of its own, in a `.cls` file. Its name (the file name without `.cls`)
becomes a type, like `Long` or `String`, and each `New` makes another object of that type.
Here is `Counter.cls`:

<!-- project: examples/book/ex03-classes/first/First.bbp -->
```basic
' Counter.cls - a class that counts. Each New Counter has its own count.
Option Explicit

Public Name As String          ' a Public variable is a property anyone can set
Private mCount As Long         ' Private: only this class's code sees it

Private Sub Class_Initialize()
    mCount = 0
    Name = "counter"
End Sub

Public Sub Add(Optional ByVal n As Long = 1)
    mCount = mCount + n
End Sub

Public Property Get Count() As Long
    Count = mCount
End Property
```

and the program that uses it, `Main.bas`:

<!-- project: examples/book/ex03-classes/first/First.bbp -->
```basic
Sub Main()
    Dim apples As Counter, pears As Counter
    Set apples = New Counter
    Set pears = New Counter
    apples.Name = "apples"
    pears.Name = "pears"
    apples.Add
    apples.Add 4
    pears.Add 2
    Print apples.Name; apples.Count
    Print pears.Name; pears.Count
End Sub
```

The project `First.bbp` lists the class with a `Class=` line:

```ini
Name=First
Startup=Sub Main
Module=Main.bas
Class=Counter.cls
```

`boing run First.bbp` prints:

```output
apples 5 
pears 2 
```

- `Dim apples As Counter` makes a variable that can **refer to** a Counter; it is `Nothing`
  until `Set apples = New Counter` makes the object. Object variables are always assigned
  with `Set`.
- `Class_Initialize` runs once for each new object, before anything else.
- `Add` has an `Optional` parameter with a default, so `apples.Add` adds 1.
- `Count` is a **property**: it reads like a variable (`apples.Count`) but is a procedure
  that returns `mCount`. There is no `Property Let Count`, so nobody outside the class can
  change the count except through `Add`.

## Step 2: The Account class: data and properties

An account keeps its data in `Private` variables, and lets the program see them through
properties. A `Property Let` runs when the program assigns to the property, so it can refuse
a bad value with `Err.Raise`:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
Private mNumber As Long
Private mOwner As String
Private mBalance As Currency
Private mLimit As Currency            ' how far below zero the balance may go

Public Property Get Owner() As String
    Owner = mOwner
End Property

' A Property Let can check the value before it keeps it.
Public Property Let Owner(ByVal value As String)
    If Trim(value) = "" Then Err.Raise 5, "Account", "An account needs an owner"
    mOwner = Trim(value)
End Property
```

`Err.Raise number, source, description` makes a run-time error, just like the built-in ones.
The program can catch it with `On Error`. Error 5 is "Invalid procedure call or argument".

`Number` and `Balance` have only a `Property Get`: the program can read them, but only the
class changes them. `Currency` is a type for money: a number with exactly four decimal places,
so adding up pennies never gives rounding errors as `Double` can.

Each account gets the next number in `Class_Initialize`. The count of numbers given out is a
`Public` variable of `Main.bas` (`Public lastNumber As Long`), because it belongs to all
accounts, not to one:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
Private Sub Class_Initialize()
    lastNumber = lastNumber + 1       ' a Public variable of Main.bas, shared by all accounts
    mNumber = 1000 + lastNumber
End Sub

' Runs when the last reference to the object goes away.
Private Sub Class_Terminate()
    Print "(account"; mNumber; "closed)"
End Sub
```

## Step 3: Events

An account should not decide alone what happens when it is overdrawn, nor print anything
itself when the balance changes: that is the program's job. So it **raises events**. The
class declares them at the top:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
Public Event Changed(ByVal amount As Currency, ByVal newBalance As Currency)
Public Event Overdrawn(ByVal amount As Currency, Cancel As Boolean)
```

and raises them with `RaiseEvent` where they happen:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
' Returns True if the money was paid out.
Public Function Withdraw(ByVal amount As Currency) As Boolean
    Dim cancel As Boolean
    If amount <= 0 Then Err.Raise 5, "Account", "Withdraw a positive amount"
    If mBalance - amount < -mLimit Then Exit Function      ' over the limit: never
    If mBalance - amount < 0 Then
        RaiseEvent Overdrawn(amount, cancel)                ' the handler may say no
        If cancel Then Exit Function
    End If
    mBalance = mBalance - amount
    RaiseEvent Changed(-amount, mBalance)
    Withdraw = True
End Function
```

`Cancel` is passed **by reference** (there is no `ByVal`), so the handler can set it to
`True` and the class sees the change after `RaiseEvent` returns. That is how a handler
answers back. `ByVal` arguments are only information.

To receive an object's events, declare the variable that holds it `WithEvents`, and write
Subs named *variable*`_`*event*:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
Sub current_Changed(ByVal amount As Currency, ByVal newBalance As Currency)
    Print "  "; IIf(amount > 0, "in ", "out"); " "; Format(Abs(amount), "0.00"); ", balance now "; Format(newBalance, "0.00")
End Sub

Sub current_Overdrawn(ByVal amount As Currency, Cancel As Boolean)
    Print "  warning: taking "; Format(amount, "0.00"); " overdraws account"; current.Number
    If Not allowOverdraft Then Cancel = True
End Sub
```

The declaration is at module level: `Dim WithEvents current As Account`. The handlers are
called for whichever account `current` refers to at the moment; `Set current = Nothing`
stops them. A `WithEvents` variable must have a class type (not `Object` or `Variant`), and
can be in a class module or an ordinary module, as here.

`IIf(condition, a, b)` gives `a` when the condition is true, else `b`.
`Format(x, "0.00")` writes a number with two decimals.

## Step 4: A Collection of accounts

The bank keeps every account in a Collection, with the account number as its key.
`OpenAccount` makes an account, fills in its properties and adds it:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
Sub OpenAccount(ByVal who As String, ByVal limit As Currency)
    Dim a As Account
    Set a = New Account               ' Class_Initialize runs here
    a.Owner = who
    a.Limit = limit
    accounts.Add a, CStr(a.Number)    ' the key must be a String
    Print "Opened account"; a.Number; "for "; a.Owner
End Sub
```

A Collection's key must be a String, so `CStr` turns the number into one. Later
`accounts("1002")` finds Bob's account by key, and `accounts(1)` finds the first account by
position. `For Each` goes through them all; with an object variable (`Dim a As Account`) as
the loop variable, you get each account in turn:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
Sub Statement()
    Dim a As Account, total As Currency
    Print "No.   Owner        Balance"
    For Each a In accounts
        Print a.Summary()
        total = total + a.Balance
    Next
    Print "Total in the bank: "; Format(total, "0.00")
End Sub
```

## Step 5: The main program

`Main` opens three accounts, tries a bad owner name (caught with `On Error Resume Next`, which
carries on with the next line and leaves the error in `Err`), works on two accounts through
`current`, prints the statement and closes an account:

<!-- project: examples/book/ex03-classes/Bank.bbp -->
```basic
    ' close Cleo's account: removing the last reference ends the object
    Print
    Set a = accounts("1003")
    accounts.Remove "1003"
    Print "Removed from the bank;"; accounts.Count; "accounts left"
    Set a = Nothing                   ' Class_Terminate runs now
    Print "Done."
```

An object lives as long as something refers to it. After `accounts.Remove` the variable `a`
still holds Cleo's account; when `a` is set to `Nothing` there is no reference left, and
`Class_Terminate` runs at once.

The whole program prints (this is `expected.out`):

```output
Opened account 1001 for Ann
Opened account 1002 for Bob
Opened account 1003 for Cleo
Rename: error 5 - An account needs an owner

Working on Ann's account:
  in  120.00, balance now 120.00
  out 30.50, balance now 89.50
  refused: over the limit
Working on Bob's account:
  in  20.00, balance now 20.00
  warning: taking 45.00 overdraws account 1002 
  refused by the handler
  warning: taking 45.00 overdraws account 1002 
  out 45.00, balance now -25.00

No.   Owner        Balance
1001  Ann            89.50
1002  Bob           -25.00
1003  Cleo            0.00
Total in the bank: 64.50

Removed from the bank; 2 accounts left
(account 1003 closed)
Done.
```

## Running it

```sh
boing run Bank.bbp
```

In AmiForge, start from a **Boing BASIC Console App**, add a new file `Account.cls` to the
project (AmiForge adds the `Class=` line to the `.bbp`), and press **Ctrl-F5**. While you type
`current.`, completion lists the members of the `Account` class.

## Try this

1. Add a `Transfer(toAccount As Account, amount As Currency)` method that withdraws from one
   account and deposits into the other, and refuses if the withdrawal is refused.
2. Add a `Property Get History() As String` that lists the last five changes. Keep them in a
   Collection inside each account (create it in `Class_Initialize`).
3. Add interest: a method `AddInterest(ratePercent As Double)` that raises `Changed` too.
4. Write an `Auditor` class that holds an account `WithEvents` and counts its changes. Make
   one auditor for each account and keep them in a second Collection, so every account is
   watched at once.
5. Let the user type commands (`open Dan`, `pay 1001 50`, `take 1002 20`, `list`) with the
   parser from [Exercise 2](02-adventure.md).

## See also

- [Classes and objects](../11-classes.md), [Procedures](../05-procedures.md) (Property
  procedures), [Errors](../08-errors.md) (`Err.Raise`, `On Error`)
- Previous: [Exercise 2: A text adventure](02-adventure.md).
  Next: [Exercise 4: Your first form](04-first-form.md)
