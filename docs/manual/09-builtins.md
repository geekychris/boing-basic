# Built-in functions

Boing BASIC has a large set of built-in functions for working with text, numbers, dates and
times, and for asking about values and the system the program runs on. This chapter describes
them group by group, with examples. Functions for files and directories are in
[Files and the system](10-files.md); those for forms, graphics, sound and the operating system
are in their own chapters. [Appendix B](appendix-b-functions.md) lists every built-in
alphabetically.

## Calling a built-in function

A built-in function is called like one of your own: its name, then its arguments in brackets.
It gives a value that you use in an expression:

*Listing 9.1* (`examples/book/ch09-builtins/listing-09-01.bas`)

<!-- run -->
```basic
Dim s As String
s = "Workbench"
Print Len(s); UCase(s); " "; Left(s, 4)
```

```output
 9 WORKBENCH Work
```

Some things to know about all of them:

- **Optional arguments.** Arguments shown in square brackets in this chapter, such as the
  `[, length]` of `Mid(s, start [, length])`, can be left out. You can also leave out an
  argument in the middle by writing nothing between the commas: `Replace(s, "a", "b", , 2)`.
- **Functions without arguments**, such as `Now`, `Timer` and `Rnd`, are written without
  brackets (`Now()` works too).
- **The `$` forms.** Functions that return a String can also be written with a `$` at the end:
  `Left$`, `Mid$`, `UCase$`, `Chr$`, `Str$`, `Format$` and so on. `Left$(s, 2)` and
  `Left(s, 2)` are the same function; the `$` only makes it clear that the result is a String.
  The functions with a `$` form are: `Left Right Mid LCase UCase Trim LTrim RTrim Space String
  Chr ChrW Str Hex Oct Format Command Environ Error InputBox Input Dir CurDir`.
- **Built-in statements.** A few built-ins are statements rather than functions, because they do
  something instead of returning a value: `Randomize`, `Beep`, `Sleep`, and the file statements
  such as `Kill`. They are written without brackets: `Sleep 500`.
- **Errors.** A built-in given an argument it cannot use raises a run-time error, usually 5
  "Invalid procedure call or argument" (for example `Left(s, -1)` or `Sqr(-1)`), 13 "Type
  mismatch" (a string that is not a number where a number is needed) or 94 "Invalid use of
  Null". See [Errors and error handling](08-errors.md).

## Strings

Boing BASIC strings hold 8-bit characters in the ISO-8859-1 (Latin-1) character set that
AmigaOS uses. A string can be any length, including empty (`""`). Character positions start at
1.

### Length and pieces

| Function | Result |
|---|---|
| `Len(s)` | the number of characters in `s` |
| `Left(s, n)` | the first `n` characters (all of `s` if it is shorter) |
| `Right(s, n)` | the last `n` characters |
| `Mid(s, start [, length])` | `length` characters from position `start`; without `length`, the rest of the string. A `start` past the end gives `""` |

*Listing 9.2* (`examples/book/ch09-builtins/listing-09-02.bas`)

<!-- run -->
```basic
Dim s As String
s = "Hello, Amiga"
Print Len(s)
Print "["; Left(s, 5); "] ["; Right(s, 5); "] ["; Mid(s, 8, 3); "] ["; Mid(s, 8); "]"
Print "["; Left(s, 50); "] ["; Mid(s, 99); "]"
```

```output
 12 
[Hello] [Amiga] [Ami] [Amiga]
[Hello, Amiga] []
```

`Len` also gives the size in bytes of a numeric variable (`Len(x)` of a Long is 4, of a Double
8) and of a user-defined type, which is useful with random-access files (see
[Files](10-files.md)).

### Changing part of a string: the Mid statement

On the left of `=`, `Mid` (or `Mid$`) replaces characters inside a String variable without
changing its length:

*Listing 9.3* (`examples/book/ch09-builtins/listing-09-03.bas`)

<!-- run -->
```basic
Dim s As String
s = "1234567890"
Mid(s, 3, 2) = "AB"
Print s
Mid(s, 9) = "XYZ"           ' only 2 characters fit before the end
Print s
Mid(s, 1) = "--"
Print s
```

```output
12AB567890
12AB5678XY
--AB5678XY
```

`Mid(variable, start [, length]) = text` copies at most `length` characters of `text` (all of
it without `length`), and never goes past the end of the variable. A `start` before 1 or past
the end of the string is error 5.

### Searching

| Function | Result |
|---|---|
| `InStr([start,] s, find [, compare])` | the position of the first `find` in `s`, from position `start` (default 1); 0 if not found |
| `InStrRev(s, find [, start [, compare]])` | the position of the last `find` in `s`, searching backwards from `start` (default: the end) |
| `StrComp(a, b [, compare])` | -1 if `a` sorts before `b`, 0 if they are equal, 1 if after |

The `compare` argument chooses how letters are compared: `vbBinaryCompare` (0) compares
character codes exactly, so "a" and "A" differ; `vbTextCompare` (1) ignores the difference
between capital and small letters, also for Latin-1 letters such as "e" with an accent. Without
it, the module's `Option Compare` setting is used (`Option Compare Binary` unless the module
says `Option Compare Text`; see [Data](04-data.md)).

*Listing 9.4* (`examples/book/ch09-builtins/listing-09-04.bas`)

<!-- run -->
```basic
Dim s As String
s = "one two one two"
Print InStr(s, "two"); InStr(6, s, "two"); InStr(s, "three"); InStr(s, "TWO")
Print InStr(1, s, "TWO", vbTextCompare)
Print InStrRev(s, "one"); InStrRev(s, "one", 8)
Print StrComp("apple", "banana"); StrComp("pear", "pear"); StrComp("Zoo", "apple")
Print StrComp("Zoo", "apple", vbTextCompare)
```

```output
 5  13  0  0 
 5 
 9  1 
-1  0 -1 
 1 
```

With binary comparison, every capital letter sorts before every small letter ("Zoo" before
"apple"), because of their character codes. For pattern matching (`s Like "A*"`), see
[Expressions](07-expressions.md).

### Changing case, trimming, building

| Function | Result |
|---|---|
| `UCase(s)`, `LCase(s)` | `s` in capitals / small letters (Latin-1 letters too) |
| `Trim(s)`, `LTrim(s)`, `RTrim(s)` | `s` without spaces at both ends / the start / the end. Only spaces are removed, not tabs or new lines |
| `Space(n)` | `n` spaces |
| `String(n, char)` | `n` copies of a character; `char` is a string (its first character is used) or a character code |
| `StrReverse(s)` | `s` backwards |
| `Replace(s, find, with [, start [, count [, compare]]])` | `s` with each `find` replaced by `with` |

*Listing 9.5* (`examples/book/ch09-builtins/listing-09-05.bas`)

<!-- run -->
```basic
Print "["; Trim("  padded  "); "]["; LTrim("  padded  "); "]["; RTrim("  padded  "); "]"
Print UCase("Boing Ball"); " "; LCase("Boing Ball")
Print "["; Space(4); "]"; String(5, "*"); String(3, 65); " "; StrReverse("Amiga")
```

```output
[padded][padded  ][  padded]
BOING BALL boing ball
[    ]*****AAA agimA
```

`Replace` replaces every match unless you give `count` (the maximum number of replacements).
With `start`, the result begins at position `start`: the characters before it are dropped, not
kept.

*Listing 9.6* (`examples/book/ch09-builtins/listing-09-06.bas`)

<!-- run -->
```basic
Print Replace("a-b-c-d", "-", " + ")
Print Replace("a-b-c-d", "-", "", 1, 2)
Print Replace("Red red RED", "red", "blue", , , vbTextCompare)
Print Replace("one two one", "one", "1", 5)
```

```output
a + b + c + d
abc-d
blue blue blue
two 1
```

### Fixed-width fields: LSet and RSet

`LSet var = text` and `RSet var = text` put `text` into a String variable **without changing the
variable's length**: `LSet` puts it on the left and fills the rest with spaces, `RSet` on the
right. Text that is too long is cut off on the right. They are useful for lining up columns:

*Listing 9.7* (`examples/book/ch09-builtins/listing-09-07.bas`)

<!-- run -->
```basic
Dim col As String
col = Space(8)
LSet col = "Ada"
Print "["; col; "]"
RSet col = "42.50"
Print "["; col; "]"
RSet col = "far too long"
Print "["; col; "]"
```

```output
[Ada     ]
[   42.50]
[far too ]
```

A `String * n` variable (a fixed-length string, see [Data](04-data.md)) always has `n`
characters, so plain assignment to it pads and cuts in the same way as `LSet`.

### Splitting and joining

`Split(s [, delimiter [, limit [, compare]]])` cuts a string into pieces at each `delimiter`
(default: a single space) and returns them as an array of Strings, numbered from 0.
`limit` is the most pieces you want; the last one holds the rest of the string.
`Join(array [, delimiter])` does the reverse: it joins the elements of a String or Variant array
with `delimiter` (default: a space) between them.

*Listing 9.8* (`examples/book/ch09-builtins/listing-09-08.bas`)

<!-- run -->
```basic
Dim parts() As String, i As Integer
parts = Split("red,green,,blue", ",")
Print "pieces:"; UBound(parts) + 1
For i = 0 To UBound(parts)
    Print i; "["; parts(i); "]"
Next
Print Join(parts, " / ")
parts = Split("name=Boing=Ball", "=", 2)
Print parts(0); " -> "; parts(1)
Print UBound(Split(""))
```

```output
pieces: 4 
 0 [red]
 1 [green]
 2 []
 3 [blue]
red / green /  / blue
name -> Boing=Ball
-1 
```

Two delimiters in a row give an empty piece (`parts(2)` above). Splitting an empty string gives
an empty array, whose `UBound` is -1.

There is no `Filter` function. To keep only some elements of an array, copy them in a loop.

### Characters and character codes

| Function | Result |
|---|---|
| `Asc(s)` | the code (0 to 255) of the first character of `s`; error 5 for `""` |
| `Chr(code)` | the character with that code (0 to 255; anything else is error 5) |
| `AscW(s)`, `ChrW(code)` | the same as `Asc` and `Chr`: strings are 8-bit, so there are no codes above 255 |

*Listing 9.9* (`examples/book/ch09-builtins/listing-09-09.bas`)

<!-- run -->
```basic
Print Asc("A"); Asc("abc"); Asc(" ")
Print Chr(66); Chr(111); Chr(105); Chr(110); Chr(103)
Print "say " & Chr(34) & "hello" & Chr(34)
Dim c As Integer
For c = Asc("a") To Asc("e")
    Print UCase(Chr(c));
Next
Print
```

```output
 65  97  32 
Boing
say "hello"
ABCDE
```

Some characters have names of their own: `vbCr` (13), `vbLf` (10), `vbCrLf` (13 and 10),
`vbTab` (9), `vbBack` (8), `vbFormFeed` (12), `vbVerticalTab` (11), `vbNullChar` (0), and
`vbNewLine`, which is a single line feed (10) as on AmigaOS. `vbNullString` is an empty string.

### Numbers to strings and back

| Function | Result |
|---|---|
| `Str(n)` | `n` as text, with a leading space for a positive number (as `Print` shows it) |
| `CStr(n)` | `n` as text, without the space |
| `Val(s)` | the number at the start of `s`, ignoring spaces; 0 if there is none. Never an error |
| `Hex(n)`, `Oct(n)` | `n` in hexadecimal / octal, without a prefix |
| `Format(n, pattern)` | `n` laid out by a pattern (see [Format](#format)) |

*Listing 9.10* (`examples/book/ch09-builtins/listing-09-10.bas`)

<!-- run -->
```basic
Print "["; Str(42); "]["; Str(-7); "]["; Str(0.5); "]["; CStr(42); "]"
Print Val("12 apples"); Val(" 3.5e2 "); Val("&HFF"); Val("-1 2 3"); Val("none")
Print Hex(255); " "; Hex(-1); " "; Hex(65536); " "; Oct(8); " &H"; Hex(48879)
```

```output
[ 42][-7][ .5][42]
 12  350  255 -123  0 
FF FFFF 10000 10 &HBEEF
```

`Val` reads as far as it can and stops at the first character that cannot be part of a number;
it skips spaces inside the number (`"-1 2 3"` is -123) and understands `&H` (hexadecimal) and
`&O` (octal). To check first whether a string is a number, use `IsNumeric`; to convert with an
error for bad input, use `CDbl`, `CLng` and the other conversion functions
([Expressions](07-expressions.md)).

`Hex` and `Oct` of a negative Integer show its 16-bit pattern (`Hex(-1)` is `FFFF`), and of a
negative Long its 32-bit pattern (`Hex(-1&)` is `FFFFFFFF`).

## Format

`Format(value [, pattern])` turns a number, date or string into text laid out the way you want.
Without a pattern it gives the same text as `CStr`. The pattern is either one of the **named
formats** or a pattern made of placeholder characters.

`Format` always writes the same way, whatever the user's Locale settings: a `.` before the
decimals, `,` between the thousands, `$` for currency, English names of days and months. That
is right for files, logs and anything a program reads back. For numbers and dates shown to the
user, `App.FormatNumber(x [, decimals])` and `App.FormatDate(d [, format])` use the decimal
point, thousands separator and date order the user chose in the Locale preferences (`1.234,50`
for a German user), and `App.DecimalPoint` and `App.GroupSeparator` give the separators
themselves ([The AmigaOS 4 desktop](18-desktop.md#number-and-date-formats)).

### Named formats

*Listing 9.11* (`examples/book/ch09-builtins/listing-09-11.bas`)

<!-- run -->
```basic
Print Format(1234.5, "General Number"); " | "; Format(1234.5, "Fixed"); " | "; Format(1234.5, "Standard")
Print Format(1234.5, "Currency"); " | "; Format(-1234.5, "Currency"); " | "; Format(0.256, "Percent")
Print Format(123.456, "Scientific"); " | "; Format(1, "Yes/No"); " | "; Format(0, "True/False"); " | "; Format(5, "On/Off")
```

```output
1234.5 | 1234.50 | 1,234.50
$1,234.50 | ($1,234.50) | 25.60%
1.23E+02 | Yes | False | On
```

| Name | Result |
|---|---|
| `General Number` | the number as it is, no thousands separators |
| `Fixed` | at least one digit before the point, two after |
| `Standard` | like `Fixed`, with thousands separators |
| `Currency` | a `$`, thousands separators, two decimals; negative amounts in brackets |
| `Percent` | times 100, two decimals and `%` |
| `Scientific` | `0.00E+00` |
| `Yes/No`, `True/False`, `On/Off` | `No`/`False`/`Off` for 0, the other word for anything else |

The named formats for dates are described under [Formatting dates](#formatting-dates).

### Number patterns

| Character | Meaning |
|---|---|
| `0` | a digit; shows `0` if the number has no digit in this place |
| `#` | a digit; shows nothing if the number has no digit in this place |
| `.` | the decimal point. The number is rounded to as many decimals as there are `0`/`#` after it |
| `,` | (between digits) thousands separators |
| `%` | multiplies the number by 100 and shows `%` |
| `E+` `E-` `e+` `e-` | scientific notation; `E+` always shows the sign of the exponent, `E-` only a minus |
| `"text"` | text shown as it is |
| `\c` | the character `c` shown as it is |
| other characters | such as `$ - + ( ) :` and spaces, shown as they are |

*Listing 9.12* (`examples/book/ch09-builtins/listing-09-12.bas`)

<!-- run -->
```basic
Print Format(5, "000"); " | "; Format(3.14159, "0.00"); " | "; Format(3.14159, "#.##")
Print Format(0.5, "#.##"); " | "; Format(0.5, "0.00"); " | "; Format(1234567.891, "#,##0.00")
Print Format(0.075, "0.0%"); " | "; Format(1234.5, "0.00E+00"); " | "; Format(0.000123, "0.0E-00")
Print Format(7, """No. ""0"); " | "; Format(7, "\#0"); " | "; Format(42, "$#,##0.00")
```

```output
005 | 3.14 | 3.14
.5 | 0.50 | 1,234,567.89
7.5% | 1.23E+03 | 1.2E-04
No. 7 | #7 | $42.00
```

A pattern can have up to three **sections** separated by `;`: the first is for positive
numbers, the second for negative ones (shown without the minus sign, so the section decides how
a negative number looks), the third for zero:

*Listing 9.13* (`examples/book/ch09-builtins/listing-09-13.bas`)

<!-- run -->
```basic
Dim amounts As Variant, a As Variant
amounts = Array(12.5, -3, 0)
For Each a In amounts
    Print Format(a, "0.00;(0.00);\n\i\l")
Next
```

```output
12.50
(3.00)
nil
```

### String patterns

For a string value, these placeholders apply:

| Character | Meaning |
|---|---|
| `@` | a character of the string, or a space if there are not enough |
| `&` | a character of the string, or nothing |
| `!` | fill the placeholders from the left (normally they fill from the right) |
| `<` / `>` | the whole result in small / capital letters |

*Listing 9.14* (`examples/book/ch09-builtins/listing-09-14.bas`)

<!-- run -->
```basic
Print "["; Format("abc", "@@@@@@"); "]["; Format("abc", "!@@@@@@"); "]"
Print Format("Workbench", ">"); " "; Format("Workbench", "<")
Print Format("5551234", "&&&-&&&&")
```

```output
[   abc][abc   ]
WORKBENCH workbench
555-1234
```

## Maths

### Arithmetic functions

| Function | Result |
|---|---|
| `Abs(x)` | `x` without its sign |
| `Sgn(x)` | -1, 0 or 1 for a negative, zero or positive `x` |
| `Int(x)` | the largest whole number not greater than `x` (rounds down: `Int(-2.5)` is -3) |
| `Fix(x)` | `x` without its fraction (rounds towards zero: `Fix(-2.5)` is -2) |
| `Round(x [, decimals])` | `x` rounded to `decimals` places (default 0); halves go to the even digit |
| `Sqr(x)` | the square root; error 5 for a negative `x` |
| `Exp(x)` | e (2.71828...) to the power `x` |
| `Log(x)` | the natural logarithm (base e); error 5 if `x` is 0 or less |
| `Sin(a)`, `Cos(a)`, `Tan(a)` | sine, cosine and tangent of an angle in **radians** |
| `Atn(x)` | the arctangent, in radians (-pi/2 to pi/2) |

*Listing 9.15* (`examples/book/ch09-builtins/listing-09-15.bas`)

<!-- run -->
```basic
Print Abs(-7.5); Sgn(-7.5); Sgn(0); Sgn(3)
Print Int(2.7); Int(-2.7); Fix(2.7); Fix(-2.7)
Print Round(2.5); Round(3.5); Round(-2.5); Round(3.14159, 2); Round(2.675, 2)
Print Sqr(144); Exp(0); Log(Exp(3)); Log(1000) / Log(10)
```

```output
 7.5 -1  0  1 
 2 -3  2 -2 
 2  4 -2  3.14  2.68 
 12  1  3  3 
```

`Round` uses **banker's rounding**: a value exactly half-way goes to the nearest even number, so
`Round(2.5)` is 2 and `Round(3.5)` is 4. This avoids a bias when many rounded values are added.
`CInt` and `CLng` round the same way. To round halves always upwards, use `Int(x + 0.5)`.

`Abs`, `Int`, `Fix` and `Round` keep the type of their argument: `Int` of a Long is that Long,
`Int` of a Double is a Double (which can hold whole numbers far beyond a Long). Assign the
result to an Integer or Long variable, or use `CLng`, when you need a whole-number type.

There is no built-in for pi, logarithms to other bases, or angles in degrees, but they are
simple to make:

*Listing 9.16* (`examples/book/ch09-builtins/listing-09-16.bas`)

<!-- run -->
```basic
Const PI As Double = 3.14159265358979

Function Deg2Rad(ByVal d As Double) As Double
    Deg2Rad = d * PI / 180
End Function

Function Log10(ByVal x As Double) As Double
    Log10 = Log(x) / Log(10)
End Function

Print Format(Atn(1) * 4, "0.000000"); " "; Format(Sin(Deg2Rad(30)), "0.000"); " "; Log10(1000)
```

```output
3.141593 0.500  3 
```

The arithmetic operators (`+ - * / \ Mod ^`) are described in [Expressions](07-expressions.md).

### Random numbers

`Rnd` gives a random Single from 0 up to (but not including) 1. `Randomize` starts the sequence
at a different place each run, from the clock; `Randomize n` starts it at a place chosen by `n`,
so the same `n` gives the same sequence each time:

*Listing 9.17* (`examples/book/ch09-builtins/listing-09-17.bas`)

<!-- run -->
```basic
Dim i As Integer
Randomize 42
For i = 1 To 6
    Print Int(Rnd * 6) + 1;       ' a dice throw: 1 to 6
Next
Print
```

```output
 3  4  2  4  6  1 
```

Without `Randomize`, a program gets the same sequence every time it runs, which can help while
testing. Call `Randomize` (with no argument) once at the start of a game. `Int(Rnd * n) + low`
gives a whole number from `low` to `low + n - 1`.

`Rnd(x)` with an argument: a negative `x` restarts the sequence at a place chosen by `x` (so
`Rnd(-1)` always gives the same number), 0 gives the last number again, and a positive `x` is
the same as `Rnd`.

### Bit shifts and fixed-point arithmetic

These functions work on Longs (32-bit whole numbers). They are mostly for graphics, games and
calling the operating system, where values are packed into bits or fixed-point numbers are
faster than Doubles.

| Function | Result |
|---|---|
| `Shl(x, n)` | `x` shifted left by `n` bits (0 to 31; anything else is error 5) |
| `ShrA(x, n)` | `x` shifted right by `n` bits, keeping the sign (arithmetic shift: rounds towards minus infinity) |
| `ShrL(x, n)` | `x` shifted right by `n` bits, filling with 0 bits (logical shift: treats `x` as unsigned) |
| `MulShr(a, b, k)` | `(a * b)` shifted right by `k` bits, with a 64-bit product so that nothing is lost on the way |
| `MulDiv(a, b, c)` | `a * b \ c` with a 64-bit product; truncates towards zero; error 11 if `c` is 0 |

A result that does not fit in a Long is error 6, "Overflow".

*Listing 9.18* (`examples/book/ch09-builtins/listing-09-18.bas`)

<!-- run -->
```basic
Print Shl(1, 10); ShrA(-16, 2); ShrL(-16, 28); Hex(Shl(&HFF, 8) Or &HAB)
' 16.16 fixed point: 1.5 * 2.25
Dim a As Long, b As Long
a = 1.5 * 65536: b = 2.25 * 65536
Print MulShr(a, b, 16) / 65536
Print MulDiv(1000000, 3000, 7000)       ' 1000000 * 3000 does not fit in a Long
```

```output
 1024 -4  15 FFAB
 3.375 
 428571 
```

## Dates and times

### Date values

A Date holds a date and a time of day together. Inside, it is a number of days since 30
December 1899: the whole part is the day and the fraction is the time (0.5 is noon). You can
write a date in a program between `#` signs, in month/day/year order or as year-month-day:
`#3/9/2024#`, `#2024-03-09#`, `#2:05:09 PM#`, `#3/9/2024 14:05#`.

A Date prints (and converts to a String) in the form month/day/year and a 12-hour time:

*Listing 9.19* (`examples/book/ch09-builtins/listing-09-19.bas`)

<!-- run -->
```basic
Dim d As Date
d = #3/9/2024 2:05:09 PM#
Print d
Print #2024-12-25#
Print #6:30:00 AM#
Print d + 1; " | "; d - #3/1/2024#
```

```output
3/9/2024 2:05:09 PM
12/25/2024
6:30:00 AM
3/10/2024 2:05:09 PM |  8.58690972222394 
```

Because a Date is a number of days, adding 1 gives the next day, and subtracting two Dates gives
the number of days between them. For other units, use `DateAdd` and `DateDiff`. To show a date
another way (for example day/month/year, as in Europe), use `Format`.

### The current date and time

| Function | Result |
|---|---|
| `Now` | the current date and time |
| `Date` | today's date (time 0:00:00) |
| `Time` | the current time of day (date part 0) |
| `Timer` | seconds since midnight, as a Single, with fractions |
| `TimerMs` | milliseconds from a fixed starting point, as a Double. Good for measuring how long something takes and for timing game loops |

*Listing 9.20* (`examples/book/ch09-builtins/listing-09-20.bas`)

```basic
Dim t As Double, i As Long, total As Double
Print "Today is "; Format(Date, "dddd d mmmm yyyy"); ", the time is "; Format(Time, "hh:nn")
t = TimerMs
For i = 1 To 100000
    total = total + Sqr(i)
Next
Print "That took"; Int(TimerMs - t); "ms"
```

`Date` and `Time` are functions only: they cannot be assigned to set the system clock. Use
`TimerMs` rather than `Timer` to measure time: `Timer` jumps back to 0 at midnight.

### Building and taking apart dates

| Function | Result |
|---|---|
| `DateSerial(year, month, day)` | a Date. Out-of-range months and days carry over: `DateSerial(2024, 13, 1)` is 1 January 2025, day 0 is the last day of the month before. Years 0 to 29 mean 2000 to 2029, 30 to 99 mean 1930 to 1999 |
| `TimeSerial(hour, minute, second)` | a time (values carry over in the same way) |
| `DateValue(x)` | the date part of a Date or a date string |
| `TimeValue(x)` | the time part |
| `Year(d)`, `Month(d)`, `Day(d)` | the year, month (1 to 12) and day (1 to 31) |
| `Hour(d)`, `Minute(d)`, `Second(d)` | the hour (0 to 23), minute and second |
| `Weekday(d [, firstday])` | the day of the week, 1 to 7; by default 1 is Sunday (`vbSunday`). With `firstday` (`vbMonday` and so on) that day is 1 |
| `MonthName(m [, abbreviate])` | "January" ... "December"; with `True`, "Jan" ... "Dec" |
| `WeekdayName(n [, abbreviate])` | "Sunday" ... "Saturday" for 1 to 7; with `True`, "Sun" ... "Sat" |

*Listing 9.21* (`examples/book/ch09-builtins/listing-09-21.bas`)

<!-- run -->
```basic
Dim d As Date
d = DateSerial(2024, 3, 9) + TimeSerial(14, 5, 9)
Print Year(d); Month(d); Day(d); Hour(d); Minute(d); Second(d)
Print Weekday(d); WeekdayName(Weekday(d)); " "; MonthName(Month(d)); " "; MonthName(Month(d), True)
Print Weekday(d, vbMonday); WeekdayName(Weekday(d), True)
Print DateSerial(2024, 2, 30); " | "; DateSerial(2024, 3, 0); " | "; DateSerial(24, 13, 1)
Print DateValue(d); " | "; TimeValue(d); " | "; TimeSerial(0, 90, 0)
```

```output
 2024  3  9  14  5  9 
 7 Saturday March Mar
 6 Sat
3/1/2024 | 2/29/2024 | 1/1/2025
3/9/2024 | 2:05:09 PM | 1:30:00 AM
```

`DateSerial(year, month + 1, 0)` is the last day of a month, a common trick.

The constants `vbSunday` (1), `vbMonday` (2), ... `vbSaturday` (7) name the days.

### Date arithmetic: DateAdd, DateDiff, DatePart

These three take an **interval** string that says which unit to count in:

| Interval | Unit |
|---|---|
| `"yyyy"` | years |
| `"q"` | quarters |
| `"m"` | months |
| `"y"` | days of the year (as `"d"` for DateAdd and DateDiff) |
| `"d"` | days |
| `"w"` | DateAdd: days; DateDiff: whole 7-day periods; DatePart: the day of the week |
| `"ww"` | weeks (DateDiff counts the Sundays crossed; DatePart gives the week of the year) |
| `"h"` | hours |
| `"n"` | minutes (`n`, because `m` is months) |
| `"s"` | seconds |

An unknown interval is error 5.

- `DateAdd(interval, number, date)` adds `number` intervals (negative to go back). Adding
  months keeps the day where it can, and otherwise uses the last day of the month: one month
  after 31 January is 28 or 29 February.
- `DateDiff(interval, date1, date2)` counts how many interval **boundaries** lie between the
  two dates (positive if `date2` is later). So `DateDiff("yyyy", #12/31/2023#, #1/1/2024#)` is
  1 although only a day has passed.
- `DatePart(interval, date)` gives one part of a date: the year, quarter, month, day of the
  year, day, day of the week, week of the year, hour, minute or second.

*Listing 9.22* (`examples/book/ch09-builtins/listing-09-22.bas`)

<!-- run -->
```basic
Dim d As Date
d = #1/31/2024 10:00:00 AM#
Print DateAdd("m", 1, d); " | "; DateAdd("yyyy", -1, d); " | "; DateAdd("ww", 2, d)
Print DateAdd("h", 36, d); " | "; DateAdd("n", -90, d)
Print DateDiff("d", #1/1/2024#, #3/1/2024#); DateDiff("m", #11/15/2023#, #2/1/2024#)
Print DateDiff("yyyy", #12/31/2023#, #1/1/2024#); DateDiff("h", #1/1/2024#, #1/2/2024 6:00:00 AM#)
Print DatePart("q", #8/15/2024#); DatePart("y", #2/1/2024#); DatePart("ww", #2/1/2024#)
```

```output
2/29/2024 10:00:00 AM | 1/31/2023 10:00:00 AM | 2/14/2024 10:00:00 AM
2/1/2024 10:00:00 PM | 1/31/2024 8:30:00 AM
 60  3 
 1  30 
 3  32  5 
```

`DateDiff` and `DatePart` accept a fourth and fifth argument (the first day of the week and of
the year) so that programs that pass them compile, but they are ignored: weeks always start on
Sunday. The same goes for a third argument to `WeekdayName`.

### Dates from strings

`CDate(s)` turns a string into a Date, and `IsDate(s)` says whether that would work. They
understand month/day/year (`"3/9/2024"`), year-month-day (`"2024-03-09"`), month names
(`"March 9, 2024"`, `"9 Mar 2024"`) and times with or without AM/PM (`"14:05"`,
`"2:05 PM"`). Three numbers are always read as month/day/year, or as year-month-day when the
first one is a year: `"5/12/2024"` is 12 May, and `"31/12/2024"` is not a date at all:

*Listing 9.23* (`examples/book/ch09-builtins/listing-09-23.bas`)

<!-- run -->
```basic
Print CDate("2024-03-09"); " | "; CDate("March 9, 2024 2:05 PM"); " | "; CDate("9 Mar 2024")
Print CDate("5/12/2024"); " | "; IsDate("12/31/2024"); IsDate("31/12/2024"); IsDate("tomorrow")
```

```output
3/9/2024 | 3/9/2024 2:05:00 PM | 3/9/2024
5/12/2024 | TrueFalseFalse
```

### Formatting dates

`Format` with a date gives full control over how it looks. The named date formats:

| Name | Example (9 March 2024, 14:05:09) |
|---|---|
| `General Date` | `3/9/2024 2:05:09 PM` |
| `Long Date` | `Saturday, March 9, 2024` |
| `Medium Date` | `09-Mar-24` |
| `Short Date` | `3/9/2024` |
| `Long Time` | `2:05:09 PM` |
| `Medium Time` | `02:05 PM` |
| `Short Time` | `14:05` |

And the characters for date patterns:

| Characters | Meaning |
|---|---|
| `d`, `dd` | day of the month, `9` / `09` |
| `ddd`, `dddd` | day name, `Sat` / `Saturday` |
| `ddddd`, `dddddd` | the short date / the long date |
| `w`, `ww` | day of the week (1 = Sunday) / week of the year |
| `m`, `mm` | month, `3` / `03` (minutes when straight after an hour, or before `:s`) |
| `mmm`, `mmmm` | month name, `Mar` / `March` |
| `q` | quarter, 1 to 4 |
| `y` | day of the year |
| `yy`, `yyyy` | year, `24` / `2024` |
| `h`, `hh` | hour, `2` / `02` |
| `n`, `nn` | minute, `5` / `05` |
| `s`, `ss` | second, `9` / `09` |
| `ttttt` | the time, `2:05:09 PM` |
| `c` | the date and time as `General Date` |
| `AM/PM`, `am/pm`, `A/P`, `a/p` | the 12-hour clock, with this marker |
| `/ : - , .` and spaces | shown as they are |
| `"text"`, `\c` | text shown as it is |

*Listing 9.24* (`examples/book/ch09-builtins/listing-09-24.bas`)

<!-- run -->
```basic
Dim d As Date
d = #3/9/2024 2:05:09 PM#
Print Format(d, "dd/mm/yyyy"); " | "; Format(d, "yyyy-mm-dd hh:nn:ss"); " | "; Format(d, "d mmm yy")
Print Format(d, "dddd, d mmmm"); " | "; Format(d, "h:nn AM/PM"); " | "; Format(d, "hh\h nn\m")
Print Format(d, "Long Date"); " | "; Format(d, "Short Time"); " | "; Format(d, """week ""ww"", day ""y")
```

```output
09/03/2024 | 2024-03-09 14:05:09 | 9 Mar 24
Saturday, 9 March | 2:05 PM | 14h 05m
Saturday, March 9, 2024 | 14:05 | week 10, day 69
```

Day and month names are in English. For dates in the user's language and order, use
`App.FormatDate` ([chapter 18](18-desktop.md#number-and-date-formats)).

## Conversions

These functions convert a value to a particular type. They are described in detail in
[Expressions](07-expressions.md):

| Function | Converts to |
|---|---|
| `CBool(x)` | Boolean |
| `CByte(x)` | Byte |
| `CInt(x)` | Integer (rounding halves to even) |
| `CLng(x)` | Long (rounding halves to even) |
| `CSng(x)` | Single |
| `CDbl(x)` | Double |
| `CCur(x)` | Currency |
| `CDec(x)` | a Variant holding a Decimal |
| `CDate(x)`, `CVDate(x)` | Date |
| `CStr(x)` | String |
| `CVar(x)` | Variant |

`Val`, `Str`, `Hex`, `Oct` and `Format` (above) also convert between numbers and strings.

## Inspecting values

These functions answer questions about a value, mostly a Variant:

| Function | True when / Result |
|---|---|
| `IsNumeric(x)` | `x` is a number, or a string that converts to one (`"12.5"`, `"1,000"`, `"&HFF"`); not for `""` |
| `IsDate(x)` | `x` is a Date, or a string `CDate` can convert |
| `IsEmpty(x)` | `x` is a Variant that has never been given a value |
| `IsNull(x)` | `x` is `Null` |
| `IsObject(x)` | `x` holds an object reference (also `Nothing`) |
| `IsArray(x)` | `x` is an array, or a Variant holding one |
| `IsMissing(x)` | an `Optional` Variant parameter was not passed (see [Procedures](05-procedures.md)) |
| `TypeName(x)` | the name of the type of `x`: "Integer", "String", "Date", "Empty", "Null", "Nothing", a class name, "Long()" for an array... |
| `VarType(x)` | the type as a number (`vbInteger` 2, `vbString` 8, `vbArray` 8192 added for arrays...) |
| `LBound(a [, dim])`, `UBound(a [, dim])` | the lowest / highest index of an array (dimension 1 unless you give `dim`) |
| `Array(a, b, ...)` | a Variant holding an array (index 0 up) of the values |

*Listing 9.25* (`examples/book/ch09-builtins/listing-09-25.bas`)

<!-- run -->
```basic
Dim v As Variant, n As Long, a(1 To 5) As String
Print IsEmpty(v); IsNumeric("12.5"); IsNumeric("12 apples"); IsNumeric("")
Print TypeName(v); " "; TypeName(n); " "; TypeName(a); " "; TypeName(Array(1, 2)); " "; TypeName(Nothing)
v = "text"
Print TypeName(v); VarType(v); IsArray(a); LBound(a); UBound(a)
v = Null
Print IsNull(v); TypeName(v)
```

```output
TrueTrueFalseFalse
Empty Long String() Variant() Nothing
String 8 True 1  5 
TrueNull
```

Arrays, `LBound` and `UBound` are described in [Data](04-data.md), and `Variant`, `Empty` and
`Null` in [Expressions](07-expressions.md).

## Choosing a value: IIf and Choose

`IIf(condition, a, b)` gives `a` if the condition is true and `b` if not. `Choose(n, a, b, c,
...)` gives the `n`th of its values (1 for the first), or `Null` if there is no `n`th value:

*Listing 9.26* (`examples/book/ch09-builtins/listing-09-26.bas`)

<!-- run -->
```basic
Dim score As Integer, day As Integer
score = 72
Print IIf(score >= 50, "pass", "fail")
For day = 1 To 4
    Print Choose(day, "Mon", "Tue", "Wed"); " ";
Next
Print
```

```output
pass
Mon Tue Wed Null 
```

Unlike `If ... Then ... Else`, `IIf` and `Choose` work out **all** their arguments before
choosing, so `IIf(x <> 0, 1 / x, 0)` still divides by zero when `x` is 0. Use an `If` statement
when one of the choices must not be worked out. There is no `Switch` function; use `Select Case`
([Control flow](06-control-flow.md)).

## The system and the program

| Built-in | What it does |
|---|---|
| `Command` | the arguments the program was started with, as one string (see [Files and the system](10-files.md)) |
| `Environ(name)` | the value of an environment variable; `""` if it is not set |
| `Shell(command)` | runs a Shell (or host) command, waits for it to finish, and returns its return code |
| `Sleep ms` | waits `ms` milliseconds |
| `DoEvents` | lets windows, timers and other events be handled during a long calculation; returns 0 |
| `Beep` | flashes the screen (on AmigaOS, `DisplayBeep`), or sounds the terminal bell on a host |
| `RGB(red, green, blue)` | a colour value from three numbers 0 to 255, for forms and graphics |

`Environ`, `Command` and `Shell` are described with the other system functions in
[Files and the system](10-files.md). `RGB` packs red into the lowest byte, then green, then
blue (`RGB(255, 0, 0)` is 255, the same as the constant `vbRed`); see [Graphics](14-graphics.md)
for colours. There is no `QBColor`.

`Sleep` and `DoEvents` matter in programs with windows: while your code runs, the program does
not react to the mouse or redraw its windows. A long loop should call `DoEvents` now and then.
Both also check for Ctrl-C (see [Errors](08-errors.md)).

*Listing 9.27* (`examples/book/ch09-builtins/listing-09-27.bas`)

<!-- run -->
```basic
Dim t As Double
t = TimerMs
Sleep 200
Print "slept at least 200 ms: "; TimerMs - t >= 200
```

```output
slept at least 200 ms: True
```

## Summary

- Strings: `Len Left Right Mid InStr InStrRev StrComp UCase LCase Trim LTrim RTrim Space String
  StrReverse Replace Split Join Asc Chr Str Val Hex Oct`, the `Mid` statement and `LSet`/`RSet`.
- `Format` lays out numbers, dates and strings with named formats or patterns.
- Maths: `Abs Sgn Int Fix Round Sqr Exp Log Sin Cos Tan Atn Rnd Randomize`, plus `Shl ShrA ShrL
  MulShr MulDiv` for bits and fixed point.
- Dates: `Now Date Time Timer TimerMs DateSerial TimeSerial DateValue TimeValue Year Month Day
  Hour Minute Second Weekday MonthName WeekdayName DateAdd DateDiff DatePart`.
- Values: `IsNumeric IsDate IsEmpty IsNull IsObject IsArray IsMissing TypeName VarType LBound
  UBound Array IIf Choose`.
- Not available: `Filter`, `Switch`, `QBColor`.

See also: [Expressions](07-expressions.md), [Files and the system](10-files.md),
[All built-in functions](appendix-b-functions.md).
