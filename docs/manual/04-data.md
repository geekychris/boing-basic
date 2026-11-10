# Program structure and data

This chapter covers the building blocks of every Boing BASIC program: how a program is laid
out, the lexical rules (lines, comments, names and literals), the `Option` statements, the data
types and their ranges, and how you declare variables, constants, enumerations, arrays and
user-defined types. Procedures and modules are in [chapter 5](05-procedures.md), and operators
and conversions in [chapter 7](07-expressions.md).

## The shape of a program

The smallest program is one line:

*Listing 4.1* (`examples/book/ch04-data/listing-04-01.bas`)

<!-- run -->
```basic
Print "Hello from Boing BASIC"
```

```output
Hello from Boing BASIC
```

A program is either a single `.bas` file or a project (`.bbp`) that lists several modules,
class modules and forms. The program starts in one of three ways:

- **Statements at module level.** If the startup module (a lone `.bas` file, or the first
  module listed in the project) has statements outside any procedure, those statements are
  the main program. They run from top to bottom, and the program ends after the last one.
- **`Sub Main`.** If the startup module has no such statements, the program runs `Sub Main`
  (from the startup module, or else from whichever module defines it).
- **A startup form.** A project with `Startup=Form Name` opens that form instead. Forms are
  described in [chapter 12](12-forms.md).

Both of these programs print the same thing:

*Listing 4.2* (`examples/book/ch04-data/listing-04-02.bas`)

<!-- run -->
```basic
Dim total As Long
total = 6 * 7
Print "The answer is"; total
```

```output
The answer is 42 
```

*Listing 4.3* (`examples/book/ch04-data/listing-04-03.bas`)

<!-- run -->
```basic
Sub Main()
    Dim total As Long
    total = 6 * 7
    Print "The answer is"; total
End Sub
```

```output
The answer is 42 
```

Procedures can sit before, between or after module-level statements. If the startup module
has module-level statements, they are the program, and `Sub Main` is then an ordinary
procedure that runs only if you call it.

Module-level statements in a module other than the startup module never run, and `boing
check` warns about them ("module-level statements in 'util' never run (only the startup
module's do): move them into a Sub"). Put code that another module needs into a procedure and
call it. Declarations (`Dim`, `Public`, `Const`, `Type`, `Enum`, `Declare`) belong at module
level in any module.

A module can bring in a file of shared declarations with `#Include "file.bi"` at the start of
a line, and a project with the key `Uses=`: each file becomes a module of its own. Both are
described in [chapter 5](05-procedures.md#sharing-code-include-and-uses).

## Lexical rules

### Lines and statements

Each statement normally takes one line. A colon `:` separates several statements on one
line, and a space followed by an underscore ` _` at the very end of a line continues the
statement on the next line:

*Listing 4.4* (`examples/book/ch04-data/listing-04-04.bas`)

<!-- run -->
```basic
Dim a As Long, b As Long
a = 1: b = 2: Print a + b
Print "This line is " & _
      "continued"
```

```output
 3 
This line is continued
```

The underscore must have a space or tab before it and nothing but spaces after it. A comment
cannot follow it. A string literal cannot be split across lines: close it and join the parts
with `&` as above.

### Comments

A comment starts with an apostrophe `'` and runs to the end of the line. `Rem` at the start
of a statement (at the start of a line, or after a `:`) is also a comment:

*Listing 4.5* (`examples/book/ch04-data/listing-04-05.bas`)

<!-- run -->
```basic
' This whole line is a comment
Rem So is this one
Print "one"    ' a comment after a statement
Print "two": Rem a Rem after a colon
```

```output
one
two
```

### Case

Keywords and names are not case-sensitive: `PRINT`, `Print` and `print` are the same
statement, and `Total`, `TOTAL` and `total` are the same variable.

### Names

A name (of a variable, constant, procedure, type, label and so on) starts with a letter, and
continues with letters, digits and underscores. It can also start with an underscore if a
letter or digit follows. Letters include the accented Latin-1 letters, so `Größe` and `été`
are valid names. There is no practical limit on the length.

Keywords such as `Dim`, `Next` or `Loop` cannot be used as names. After a dot, though, any
word is a member name, so `obj.Print` or `x.End` refer to members, not to keywords. The full
list of keywords is in [appendix A](appendix-a-keywords.md).

A few words are statements only where they start a statement in a particular form
(`Line Input`, `Name a As b`, `Put #`, `Seek #`, `Debug.Print`), so you can still use `Name`,
`Line` or `Seek` as ordinary names elsewhere.

### Labels and line numbers

A name followed by a colon at the start of a line is a label, and a number at the start of a
line is a line number. Both are targets for `GoTo`, `GoSub` and `On Error GoTo`
([chapter 6](06-control-flow.md)):

*Listing 4.6* (`examples/book/ch04-data/listing-04-06.bas`)

<!-- run -->
```basic
Dim n As Integer
10 n = n + 1
If n < 3 Then GoTo 10
Print "n is"; n
GoTo done
Print "skipped"
done:
Print "finished"
```

```output
n is 3 
finished
```

Because of this rule, a call to a procedure with no arguments, written at the start of a line
and followed by a colon, is read as a label. `Tidy: Print "x"` defines a label `Tidy` and does
not call `Tidy`. Write `Call Tidy: Print "x"`, or put the call on a line of its own.

### Literals

| Literal | Examples | Type |
|---|---|---|
| Whole number | `0`, `42`, `-7`, `100000` | `Integer` if it fits (up to 32767), else `Long`, else `Double` |
| Number with a fraction or exponent | `1.5`, `.25`, `3.`, `1E10`, `2.5E-3`, `1D3` | `Double` (`D` is the same as `E`) |
| Hexadecimal | `&HFF`, `&hff`, `&H7FFF` | `Integer` up to 4 digits, else `Long` |
| Octal | `&O17`, `&o777` | as hexadecimal |
| String | `"text"`, `""`, `"say ""hi"""` | `String`; `""` inside a string is one quote |
| Date and time | `#12/25/2026#`, `#2026-12-25#`, `#13:45:00#`, `#1:30 PM#`, `#12/25/2026 6:30 PM#` | `Date` |
| Boolean | `True`, `False` | `Boolean` (`True` is -1, `False` is 0) |
| Special values | `Empty`, `Null`, `Nothing` | see [Variant](#variant) and [Object](#object) |

A type suffix after a number forces its type: `5%` Integer, `5&` Long, `5!` Single, `5#`
Double, `5@` Currency. `%` and `&` need a whole number in range (`1.5%` and `40000%` are
compile errors).

Hexadecimal and octal numbers of up to 16 bits are Integers, so `&HFFFF` is -1 and `&H8000` is
-32768. Add `&` to get the 32-bit value: `&HFFFF&` is 65535. Eight digits give a Long, where
`&HFFFFFFFF` is -1.

A minus sign is not part of a number: `-32768` is the operator `-` applied to `32768`, which
is a Long.

Date literals are read month first (`#1/2/2026#` is 2 January 2026), or year first with
dashes (`#2026-01-02#`). Times use a 24-hour clock or `AM`/`PM`.

*Listing 4.7* (`examples/book/ch04-data/listing-04-07.bas`)

<!-- run -->
```basic
Print &HFF; &H10; &O17; &HFFFF; &HFFFF&; &HFFFFFFFF
Print 1.5E3; 2D2; .5; 1E+20
Print "She said ""Boing!"""
Print #12/25/2026 6:30:00 PM#
Print #2026-01-02#; " "; #13:45:00#
Print TypeName(1); " "; TypeName(100000); " "; TypeName(1.5); " "; TypeName(1!); " "; TypeName(1@)
```

```output
 255  16  15 -1  65535 -1 
 1500  200  .5  1E+20 
She said "Boing!"
12/25/2026 6:30:00 PM
1/2/2026 1:45:00 PM
Integer Long Double Single Currency
```

### Type suffixes on names

A name can end in a type character that gives its type. The suffix is part of how you write
the name, not part of the name itself: `count%` and `count` are the same variable.

| Suffix | Type |
|---|---|
| `%` | Integer |
| `&` | Long |
| `!` | Single |
| `#` | Double |
| `@` | Currency |
| `$` | String |

Many string functions can also be written with a `$`: `Left$`, `Mid$`, `UCase$`, `Chr$` and
so on ([chapter 9](09-builtins.md)). In Boing BASIC both forms return a String. A variable declared
with a suffix cannot also have an `As` clause (`Dim n% As Integer` is an error).

## Option statements

`Option` statements go at the top of a module, outside any procedure. Each applies to the
whole module it is in, and only to that module.

| Statement | Effect |
|---|---|
| `Option Explicit` | Every variable must be declared before use. Without it, an unknown name is declared for you (see below). |
| `Option Base 0` / `Option Base 1` | The default lower bound of arrays declared with only an upper bound (`Dim a(10)`). The default is 0. |
| `Option Compare Binary` / `Option Compare Text` | How strings compare: `Binary` (the default) by character code, so `"a" > "B"`; `Text` ignores case. It affects `=`, `<` and the other comparisons, `Like`, `InStr`, `InStrRev`, `Replace`, `Split` and `StrComp`. |
| `Option Private Module` | Accepted and ignored. |

Use `Option Explicit` in every program. It turns a misspelt variable name into a compile error
instead of a new, empty variable:

<!-- error: variable 'totl' is not defined -->
```basic
Option Explicit
Dim total As Long
total = 10
Print totl
```

*Listing 4.8* (`examples/book/ch04-data/listing-04-08.bas`)

<!-- run -->
```basic
Option Compare Text
Print "abc" = "ABC"; "apple" < "BANANA"; InStr("Boing", "O")
```

```output
TrueTrue 2 
```

## Data types

| Type | Suffix | Size | Range and notes |
|---|---|---|---|
| `Byte` | | 8 bits | 0 to 255 |
| `Boolean` | | 16 bits | `True` (-1) or `False` (0) |
| `Integer` | `%` | 16 bits | -32768 to 32767 |
| `Long` | `&` | 32 bits | -2147483648 to 2147483647 |
| `Single` | `!` | 32 bits | IEEE single precision, about 7 significant digits, up to about 3.4E38 |
| `Double` | `#` | 64 bits | IEEE double precision, about 15 significant digits, up to about 1.8E308 |
| `Currency` | `@` | 64 bits | fixed point with 4 decimal places: -922337203685477.5808 to 922337203685477.5807 |
| `Date` | | 64 bits | a date and time, 1 January 100 to 31 December 9999 |
| `String` | `$` | | text of any length, one byte per character |
| `String * n` | | n bytes | fixed-length text, n from 1 to 65535 |
| `Variant` | | | any of the above, an array, an object, `Empty` or `Null`; also the Decimal subtype |
| `Object` | | | a reference to any object, or `Nothing` |
| a class name, `Collection` | | | a reference to an object of that class ([chapter 11](11-classes.md)) |
| a `Type` name | | | a user-defined record ([below](#user-defined-types)) |
| an `Enum` name | | 32 bits | a Long ([below](#enumerations)) |

### Whole numbers

`Byte`, `Integer` and `Long` hold whole numbers. Arithmetic that goes outside a type's range
is run-time error 6, "Overflow"; it never wraps round silently. So does storing a value that
does not fit, such as 300 in a Byte. Assigning a number with a fraction to a whole-number
variable rounds it to the nearest whole number, with halves going to the even neighbour
("banker's rounding"): 2.5 becomes 2 and 3.5 becomes 4.

*Listing 4.9* (`examples/book/ch04-data/listing-04-09.bas`)

<!-- run -->
```basic
Dim i As Integer, b As Byte
i = 2.5: Print i;
i = 3.5: Print i;
i = -2.5: Print i
On Error Resume Next
i = 32767
i = i + 1
Print "Error"; Err.Number; Err.Description
```

```output
 2  4 -2 
Error 6 Overflow
```

Integer arithmetic stays Integer when both operands are Integers, which matters with
literals: `3000 * 20` overflows, because both numbers are Integers. Write `3000& * 20`, or
use a Long variable. [Chapter 7](07-expressions.md) gives the full rules.

### Floating point

`Single` and `Double` are binary floating point. They hold very large and very small
numbers, but not every decimal fraction exactly: `0.1 + 0.2` is not exactly `0.3`. A result
that would be infinite or not a number (for example an overflow) is error 6. Dividing by
zero is error 11, "Division by zero".

`Print` shows a Single to 7 significant digits and a Double to 15, and leaves out a leading
zero:

*Listing 4.10* (`examples/book/ch04-data/listing-04-10.bas`)

<!-- run -->
```basic
Dim s As Single, d As Double
s = 1 / 3
d = 1 / 3
Print s; d
Print 1E+15; 1E+16; 0.000001
```

```output
 .3333333  .333333333333333 
 1E+15  1E+16  1E-06 
```

### Currency

`Currency` is a 64-bit whole number scaled by 10000, so it has exactly four decimal places.
Use it for money and anywhere you need exact decimal addition and subtraction. Values are
rounded to four places when stored:

*Listing 4.11* (`examples/book/ch04-data/listing-04-11.bas`)

<!-- run -->
```basic
Dim price As Currency
price = 1.23456
Print price
price = 10 / 3
Print price
Print price * 3
```

```output
 1.2346 
 3.3333 
 9.9999 
```

### Decimal

There is no `Decimal` variable type. `CDec(x)` makes a Variant with the Decimal subtype: a
96-bit whole number with a decimal scale of 0 to 28 places, about 28 significant digits, up
to 79228162514264337593543950335. Arithmetic with a Decimal operand gives a Decimal. Hold
Decimals in a `Variant`:

*Listing 4.12* (`examples/book/ch04-data/listing-04-12.bas`)

<!-- run -->
```basic
Dim big As Variant
big = CDec("12345678901234567890.5")
Print big * 2
Print CDec(1) / 3
Print TypeName(big); VarType(big)
```

```output
 24691357802469135781 
 .3333333333333333333333333333 
Decimal 14 
```

`VarType` gives 14 for a Decimal, the value of the constant `vbDecimal`, so
`VarType(big) = vbDecimal` tests for one.

### Boolean

A `Boolean` is `True` or `False`. Stored as a number, `True` is -1 and `False` is 0. Any
non-zero number assigned to a Boolean becomes `True`, and the strings `"True"` and `"False"`
(in any case) convert too. A Boolean prints as `True` or `False`.

*Listing 4.13* (`examples/book/ch04-data/listing-04-13.bas`)

<!-- run -->
```basic
Dim ok As Boolean, n As Integer
ok = 7: Print ok
ok = "false": Print ok
n = True: Print n
```

```output
True
False
-1 
```

### Date

A `Date` holds a date and a time as a number of days since 30 December 1899: the whole part
is the day and the fraction is the time of day (0.5 is noon). Adding 1 to a Date moves it on
one day, and subtracting two Dates gives the number of days between them. Dates print in the
form month/day/year with a 12-hour time; a date with no time prints only the date, and a time
on day 0 prints only the time.

*Listing 4.14* (`examples/book/ch04-data/listing-04-14.bas`)

<!-- run -->
```basic
Dim d As Date
d = #1/31/2026#
Print d; " "; d + 1; " "; d - #1/1/2026#
d = #1/31/2026 3:15:00 PM#
Print d
d = 0.75
Print d
```

```output
1/31/2026 2/1/2026  30 
1/31/2026 3:15:00 PM
6:00:00 PM
```

The date and time functions (`Now`, `DateSerial`, `DateAdd`, `Format` and many more) are in
[chapter 9](09-builtins.md).

### String

A `String` holds text of any length, from none (`""`) up to the memory available. Each
character is one byte, so strings hold Latin-1 text, the AmigaOS character set, and also any
binary data. `Len(s)` is the length in bytes.

A fixed-length string, `Dim code As String * 5`, always has exactly that many characters.
Assigning a longer string cuts it to fit, and a shorter one is padded with spaces:

*Listing 4.15* (`examples/book/ch04-data/listing-04-15.bas`)

<!-- run -->
```basic
Dim code As String * 5
code = "ABCDEFGH"
Print "["; code; "]"; Len(code)
code = "AB"
Print "["; code; "]"
```

```output
[ABCDE] 5 
[AB   ]
```

Fixed-length strings are most useful as fields in user-defined types written to files
([chapter 10](10-files.md)).

### Variant

A `Variant` can hold a value of any type, and remembers which type it holds (its subtype).
A variable declared without a type (`Dim x`) is a Variant, unless a `DefType` statement
says otherwise. `TypeName` names the subtype and `VarType` gives its number:

*Listing 4.16* (`examples/book/ch04-data/listing-04-16.bas`)

<!-- run -->
```basic
Dim v As Variant
Print TypeName(v); VarType(v)
v = 5: Print TypeName(v); VarType(v)
v = 100000: Print TypeName(v); VarType(v)
v = 2.5: Print TypeName(v); VarType(v)
v = "text": Print TypeName(v); VarType(v)
v = Null: Print TypeName(v); VarType(v)
```

```output
Empty 0 
Integer 2 
Long 3 
Double 5 
String 8 
Null 1 
```

Two values exist only in Variants:

- **`Empty`** is the value of a Variant that has not been assigned. In arithmetic it acts as
  0, and in string operations as `""`. Test for it with `IsEmpty(v)`, and assign `v = Empty`
  to clear a Variant.
- **`Null`** means "no valid value". Most operators give `Null` when an operand is `Null`
  (`Null + 1` is `Null`), and `&` treats it as `""`. Test for it with `IsNull(v)`; `v = Null`
  does not work as a test, because the comparison itself gives `Null`. Passing `Null` to a
  function that needs a value, such as `Len(Null)`, is error 94, "Invalid use of Null".

*Listing 4.17* (`examples/book/ch04-data/listing-04-17.bas`)

<!-- run -->
```basic
Dim v As Variant
Print IsEmpty(v); v + 1; "[" & v & "]"
v = Null
Print IsNull(v); IsNull(v + 1); "[" & v & "]"
```

```output
True 1 []
TrueTrue[]
```

A Variant can also hold an array (see [Arrays](#arrays)) or an object. Arithmetic on Variants
does not overflow the way typed arithmetic does: an Integer result that is too big becomes a
Long, and a Long result becomes a Double. [Chapter 7](07-expressions.md) describes Variant
arithmetic and comparison in full.

Variants are convenient but slower than typed variables. Prefer a specific type where you
know what a variable will hold.

### Object

An `Object` variable, or one declared with a class name, holds a reference to an object, or
`Nothing` when it refers to none. Object references are assigned with `Set`, and compared with
`Is`:

*Listing 4.18* (`examples/book/ch04-data/listing-04-18.bas`)

<!-- run -->
```basic
Dim c As New Collection, o As Object
Print o Is Nothing
Set o = c
Print o Is c; TypeName(o)
Set o = Nothing
Print o Is Nothing
```

```output
True
TrueCollection
True
```

Objects, classes and `Collection` are the subject of [chapter 11](11-classes.md).

### Default values

Every variable starts with a value: 0 for the number types, `False` for Boolean, `""` for a
String (spaces for a fixed-length String), 0 (shown as 12:00:00 AM) for a Date, `Empty` for a
Variant and `Nothing` for an object. Each field of a user-defined type and each element of an
array starts at its own type's default.

*Listing 4.19* (`examples/book/ch04-data/listing-04-19.bas`)

<!-- run -->
```basic
Dim i As Integer, d As Double, ok As Boolean, s As String, v As Variant, o As Object
Print i; d; ok; "["; s; "]"; IsEmpty(v); o Is Nothing
```

```output
 0  0 False[]TrueTrue
```

## Declaring variables

### Dim

`Dim` declares one or more variables:

*Listing 4.20* (`examples/book/ch04-data/listing-04-20.bas`)

```basic
Dim count As Long
Dim name As String, age As Integer, height As Single
Dim total&, title$         ' with type suffixes
Dim anything               ' a Variant
count = 1
```

Each variable needs its own `As`. In `Dim a, b As Integer`, only `b` is an Integer, and `a`
is a Variant:

*Listing 4.21* (`examples/book/ch04-data/listing-04-21.bas`)

<!-- run -->
```basic
Dim a, b As Integer
Print TypeName(a); " "; TypeName(b)
```

```output
Empty Integer
```

Where you put the declaration decides the variable's scope and lifetime:

- **Inside a procedure** (`Dim`, or `Static`): a local variable, visible only in that
  procedure. A `Dim` local is created each time the procedure is called, and a `Static`
  local keeps its value between calls.
- **At module level** (`Dim` or `Private`): a module variable, visible in every procedure
  of that module and kept for the whole run. A `Dim` among module-level statements is also a
  module variable.
- **At module level with `Public`** (or `Global`, which means the same): visible in every
  module of the project.

[Chapter 5](05-procedures.md) covers scope, `Static` and modules in detail.

### Implicit declaration

Without `Option Explicit`, using a name that has not been declared declares it for you, as a
local Variant (or with the type of its suffix, or of a `DefType` letter range). This is
handy for short scripts and dangerous in anything longer, because a typing mistake silently
makes a new variable:

*Listing 4.22* (`examples/book/ch04-data/listing-04-22.bas`)

<!-- run -->
```basic
count = 5
title$ = "Boing"
Print TypeName(count); " "; TypeName(title$)
Print countt + 1          ' a misspelling: a new, empty variable
```

```output
Integer String
 1 
```

### DefType statements

A `DefType` statement at module level sets the type of everything in that module that is
declared without `As` or a suffix, by the first letter of its name. It covers variables
(implicit ones too), parameters, and the results of Functions and `Property Get`.

| Statement | Type |
|---|---|
| `DefBool` | Boolean |
| `DefByte` | Byte |
| `DefInt` | Integer |
| `DefLng` | Long |
| `DefCur` | Currency |
| `DefSng` | Single |
| `DefDbl` | Double |
| `DefDate` | Date |
| `DefStr` | String |
| `DefObj` | Object |
| `DefVar` | Variant |

Each takes letters and letter ranges, separated by commas:

*Listing 4.23* (`examples/book/ch04-data/listing-04-23.bas`)

<!-- run -->
```basic
DefInt I-N
DefStr S, T
Dim index, sName, x
index = 5.6
sName = "Ann"
Print index; " "; sName; " "; TypeName(index); " "; TypeName(sName); " "; TypeName(x)
```

```output
 6  Ann Integer String Empty
```

### Assignment

`variable = expression` stores a value, converting it to the variable's type if needed
([chapter 7](07-expressions.md#conversions)). The keyword `Let` may go in front, but it
changes nothing. An object reference is stored with `Set` instead
([Object](#object) above):

*Listing 4.24* (`examples/book/ch04-data/listing-04-24.bas`)

<!-- run -->
```basic
Dim n As Long, t As String
n = 5
Let t = "five"
n = n * 2
Print n; t
```

```output
 10 five
```

## Constants

`Const` gives a name to a value that never changes. The value must be a constant expression:
literals, other constants and operators, but no variables or function calls.

*Listing 4.25* (`examples/book/ch04-data/listing-04-25.bas`)

<!-- run -->
```basic
Const MAX_LIVES = 3
Const TITLE As String = "Boing Ball"
Const SPEED As Double = 2.5, DOUBLE_SPEED = SPEED * 2
Const MASK = &HFF00&, NEG = -MAX_LIVES
Print MAX_LIVES; TITLE; SPEED; DOUBLE_SPEED; MASK; NEG
Print TypeName(MAX_LIVES); " "; TypeName(DOUBLE_SPEED)
```

```output
 3 Boing Ball 2.5  5  65280 -3 
Integer Double
```

Without `As`, a constant takes the type of its value (here `MAX_LIVES` is an Integer). With
`As`, the value is converted to that type. Assigning to a constant is a compile error.

A `Const` inside a procedure is local to it. At module level, a `Const` is private to its
module unless declared `Public Const`. Built-in constants such as `vbCrLf`, `vbTab`,
`vbNewLine`, `vbYesNo` and `vbKeyLeft` are listed in [chapter 9](09-builtins.md).

## Enumerations

An `Enum` names a set of related whole-number constants. It is declared at module level:

*Listing 4.26* (`examples/book/ch04-data/listing-04-26.bas`)

<!-- run -->
```basic
Enum Fruit
    Apple           ' 0
    Pear            ' 1
    Plum = 10
    Fig             ' 11
    Kiwi = -1
End Enum

Dim f As Fruit
f = Fig
Print Apple; Pear; Plum; f; Fruit.Kiwi
Print TypeName(f)
```

```output
 0  1  10  11 -1 
Long
```

The first member is 0 unless given a value, and each member without a value is one more than
the one before. A value can be any constant expression. Refer to a member by its name alone,
or as `EnumName.Member` when the name alone would be ambiguous.

A variable declared with an enumeration's name is a Long. It is not limited to the members'
values: `f = 99` is allowed.

An `Enum` (like a `Type`) declared in one module can be used in all the modules of a
project; `Private Enum` keeps it to its own module.

## Arrays

An array holds many values of one type, picked out by an index in parentheses.

### Fixed-size arrays

Declare a fixed-size array with its bounds. With only an upper bound, the lower bound is 0
(or 1 under `Option Base 1`); you can also give both with `To`:

*Listing 4.27* (`examples/book/ch04-data/listing-04-27.bas`)

<!-- run -->
```basic
Dim squares(5) As Long            ' 6 elements, 0 to 5
Dim days(1 To 7) As String        ' 7 elements, 1 to 7
Dim i As Integer
For i = 0 To 5
    squares(i) = i * i
Next
days(1) = "Monday"
Print squares(4); LBound(squares); UBound(squares)
Print days(1); LBound(days); UBound(days)
```

```output
 16  0  5 
Monday 1  7 
```

The bounds of a fixed-size array must be constant expressions, and the upper bound must not
be below the lower bound. Negative bounds are allowed (`Dim t(-10 To 10)`).

Using an index outside the bounds is run-time error 9, "Subscript out of range".

### More than one dimension

An array can have up to 8 dimensions, each with its own bounds. `LBound(a, n)` and
`UBound(a, n)` give the bounds of dimension `n`:

*Listing 4.28* (`examples/book/ch04-data/listing-04-28.bas`)

<!-- run -->
```basic
Dim grid(1 To 3, 1 To 4) As Integer
Dim r As Integer, c As Integer
For r = 1 To 3
    For c = 1 To 4
        grid(r, c) = r * 10 + c
    Next
Next
Print grid(2, 3); UBound(grid, 1); UBound(grid, 2)
```

```output
 23  3  4 
```

### Dynamic arrays and ReDim

A dynamic array is declared with empty parentheses and given its size later with `ReDim`.
The bounds in `ReDim` can be any expressions, worked out when the statement runs. `ReDim`
clears the array; `ReDim Preserve` keeps the existing elements:

*Listing 4.29* (`examples/book/ch04-data/listing-04-29.bas`)

<!-- run -->
```basic
Dim names() As String
Dim n As Long
n = 2
ReDim names(n)
names(0) = "Ann": names(1) = "Bob": names(2) = "Cy"
ReDim Preserve names(4)
Print names(0); names(2); "["; names(4); "]"; UBound(names)
ReDim names(1)
Print "["; names(0); "]"; UBound(names)
```

```output
AnnCy[] 4 
[] 1 
```

The rules:

- `ReDim` can be used only on a dynamic array. `ReDim` of a fixed-size array is a compile
  error.
- `ReDim` cannot change the number of dimensions or the element type.
- `ReDim Preserve` can change only the last dimension's upper bound; changing another
  dimension is error 9.
- `ReDim` on a name that has not been declared declares a new local dynamic array, for
  example `ReDim buffer(1 To 100) As Byte`.

A dynamic array that has not been sized has no elements: `UBound` on it is error 9.

### Erase

`Erase` empties arrays. A fixed-size array keeps its size and every element goes back to its
default value; a dynamic array is freed and has no elements until the next `ReDim`:

*Listing 4.30* (`examples/book/ch04-data/listing-04-30.bas`)

<!-- run -->
```basic
Dim fixed(3) As Integer, dyn() As Integer
fixed(2) = 5
ReDim dyn(10)
Erase fixed, dyn
Print fixed(2); UBound(fixed)
On Error Resume Next
Print UBound(dyn)
Print "Error"; Err.Number; Err.Description
```

```output
 0  3 
Error 9 Subscript out of range
```

### Copying arrays

Assigning one array to another copies all its elements. The target must be a dynamic array
of the same element type; it takes the source's bounds. Assigning to a fixed-size array is a
compile error.

*Listing 4.31* (`examples/book/ch04-data/listing-04-31.bas`)

<!-- run -->
```basic
Dim src(2) As Integer, copy() As Integer
src(0) = 7: src(1) = 8: src(2) = 9
copy = src
src(0) = 0
Print copy(0); copy(2); UBound(copy)
```

```output
 7  9  2 
```

A Function can return an array (declare it `As Type()`), and arrays can be passed to
procedures; see [chapter 5](05-procedures.md).

### Arrays in Variants: Array and Split

A Variant can hold a whole array. `Array(a, b, ...)` makes a Variant array of its arguments,
always with lower bound 0 (whatever `Option Base` says); `Array()` with no arguments gives an
empty array whose `UBound` is -1. `Split` ([chapter 9](09-builtins.md)) also returns an array.
`IsArray(v)` tells you whether a Variant holds an array.

*Listing 4.32* (`examples/book/ch04-data/listing-04-32.bas`)

<!-- run -->
```basic
Dim v As Variant, parts As Variant
v = Array(10, "two", 3.5)
Print v(1); LBound(v); UBound(v); IsArray(v)
Print TypeName(v)
parts = Split("red,green,blue", ",")
Print parts(2); UBound(parts)
```

```output
two 0  2 True
Variant()
blue 2 
```

`For Each` walks through every element of an array; it is described in
[chapter 11](11-classes.md) together with collections:

*Listing 4.33* (`examples/book/ch04-data/listing-04-33.bas`)

<!-- run -->
```basic
Dim item As Variant
For Each item In Array("Amiga", "Boing", "BASIC")
    Print item
Next
```

```output
Amiga
Boing
BASIC
```

## User-defined types

A user-defined type groups several values, called fields, into one record. Declare it at
module level with `Type ... End Type`, giving every field a type:

*Listing 4.34* (`examples/book/ch04-data/listing-04-34.bas`)

<!-- run -->
```basic
Type Point
    X As Long
    Y As Long
End Type

Type Player
    Name As String
    Initials As String * 3
    Pos As Point                    ' a nested type
    Scores(1 To 3) As Integer       ' a fixed-size array field
    Lives As Integer
End Type

Dim p As Player
p.Name = "Ann"
p.Initials = "ANNE"
p.Pos.X = 10: p.Pos.Y = 20
p.Scores(2) = 500
p.Lives = 3
Print p.Name; " ["; p.Initials; "] at"; p.Pos.X; ","; p.Pos.Y; " score"; p.Scores(2)
```

```output
Ann [ANN] at 10 , 20  score 500 
```

Fields can be of any type: numbers, strings (variable or fixed-length), Variants, objects,
other user-defined types, and fixed-size arrays. A type cannot contain itself.

### Working with records

Assigning one record to another copies every field, including nested types and array fields.
You can make arrays of records, dynamic ones too, and pass records to procedures (always by
reference) or return them from Functions:

*Listing 4.35* (`examples/book/ch04-data/listing-04-35.bas`)

<!-- run -->
```basic
Type Point
    X As Long
    Y As Long
End Type

Function MakePoint(ByVal x As Long, ByVal y As Long) As Point
    MakePoint.X = x
    MakePoint.Y = y
End Function

Dim a As Point, b As Point, path() As Point, i As Integer
a = MakePoint(3, 4)
b = a                   ' a copy
b.X = 99
Print a.X; b.X
ReDim path(1 To 3)
For i = 1 To 3
    path(i) = MakePoint(i, i * i)
Next
Print path(3).X; path(3).Y
```

```output
 3  99 
 3  9 
```

`With` saves repeating the record's name ([chapter 11](11-classes.md)):

*Listing 4.36* (`examples/book/ch04-data/listing-04-36.bas`)

<!-- run -->
```basic
Type Box
    W As Long
    H As Long
End Type
Dim b As Box
With b
    .W = 3
    .H = 4
    Print .W * .H
End With
```

```output
 12 
```

### Limits of user-defined types

- `Type` is allowed only at module level, not inside a procedure.
- A record cannot be stored in a Variant, so it cannot go into a `Collection` or an
  `Array(...)`. Use a class ([chapter 11](11-classes.md)) when you need that.
- Records cannot be compared with `=`; compare their fields.
- A record cannot be passed `ByVal`.
- `For Each` does not work on an array of records; use a `For` loop with an index.

A `Type` declared in one module is available to every module of the project; `Private Type`
keeps it to its own module. Records with fixed-length fields can be written to and read from
files with `Put` and `Get` ([chapter 10](10-files.md)).

## Summary

- A program is module-level statements, or a `Sub Main`, or a startup form. Only the startup
  module's module-level statements run.
- `'` and `Rem` start comments, `:` separates statements, ` _` continues a line, and case
  never matters.
- Use `Option Explicit` and give every variable a type with `As`.
- Whole-number types raise error 6 on overflow; Variants widen instead.
- Arrays can be fixed-size or dynamic (`ReDim [Preserve]`), with up to 8 dimensions.
- `Type ... End Type` makes records, which copy on assignment.

See also: [Procedures and modules](05-procedures.md), [Control flow](06-control-flow.md),
[Expressions, operators and conversions](07-expressions.md),
[Built-in functions](09-builtins.md), [Keywords](appendix-a-keywords.md).
