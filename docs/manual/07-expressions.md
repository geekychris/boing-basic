# Expressions, operators and conversions

This chapter describes how Boing BASIC works out expressions: the arithmetic, string,
comparison and logical operators and their order of precedence, what type each result has,
what happens on overflow, how values convert from one type to another (by themselves and with
the conversion functions), and how the Variant values `Empty`, `Null` and `Nothing` behave.
`TypeName` and `VarType`, which tell you what a value is, are at the end.

## Operators at a glance

| Operator | Meaning | Example | Result |
|---|---|---|---|
| `^` | power | `2 ^ 10` | 1024 |
| `-` (unary) | negation | `-x` | |
| `*` | multiplication | `6 * 7` | 42 |
| `/` | division | `7 / 2` | 3.5 |
| `\` | whole-number division | `7 \ 2` | 3 |
| `Mod` | remainder | `7 Mod 2` | 1 |
| `+` | addition (or joining two strings) | `2 + 3` | 5 |
| `-` | subtraction | `5 - 3` | 2 |
| `&` | string concatenation | `"a" & 1` | `"a1"` |
| `=` `<>` `<` `>` `<=` `>=` | comparison | `3 < 5` | True |
| `Like` | pattern match | `"Boing" Like "B*"` | True |
| `Is` | same object | `a Is b` | |
| `Not` | logical or bitwise NOT | `Not True` | False |
| `And` | logical or bitwise AND | `6 And 3` | 2 |
| `Or` | logical or bitwise OR | `6 Or 3` | 7 |
| `Xor` | exclusive OR | `6 Xor 3` | 5 |
| `Eqv` | equivalence | `True Eqv True` | True |
| `Imp` | implication | `True Imp False` | False |

`<>` can also be written `><`. `:=` is not an operator: it names an argument in a call
([chapter 5](05-procedures.md#named-arguments)).

## Precedence

Operators higher in this list are applied first. Operators on the same line have equal
precedence and are applied from left to right. Parentheses override everything.

1. `^`
2. unary `-` and `+`
3. `*` and `/`
4. `\`
5. `Mod`
6. `+` and `-`
7. `&`
8. `=`, `<>`, `<`, `>`, `<=`, `>=`, `Like`, `Is`
9. `Not`
10. `And`
11. `Or`
12. `Xor`
13. `Eqv`
14. `Imp`

Some consequences:

- `-2 ^ 2` is -4, because `^` comes before negation. Write `(-2) ^ 2` for 4. A minus sign
  directly after `^` is allowed: `2 ^ -1` is 0.5.
- `2 ^ 3 ^ 2` is `(2 ^ 3) ^ 2`, 64.
- `7 \ 2 * 3` is `7 \ 6`, 1, because `*` comes before `\`.
- `"Total: " & a + b` adds first, then joins.
- `Not a = b` is `Not (a = b)`, and `a < b And b < c` needs no parentheses.

*Listing 7.1* (`examples/book/ch07-expressions/listing-07-01.bas`)

<!-- run -->
```basic
Print 2 + 3 * 4; (2 + 3) * 4; 10 - 2 - 3
Print -2 ^ 2; (-2) ^ 2; 2 ^ -1; 2 ^ 3 ^ 2
Print 7 \ 2 * 3; 10 Mod 4 * 2
Print "Sum: " & 1 + 2
Print Not 1 = 2; 1 < 2 And 2 < 3
```

```output
 14  20  5 
-4  4  .5  64 
 1  2 
Sum: 3
TrueTrue
```

## Arithmetic

### The operators

- `+`, `-` and `*` add, subtract and multiply.
- `/` always divides exactly, giving a Double (a Single when both operands are Singles, or a
  Single and an Integer or Byte).
- `\` divides and drops the fraction, giving a whole number. Its operands are first rounded
  to whole numbers (halves to even), then divided, and the result is truncated toward zero:
  `7.5 \ 2` is `8 \ 2`, 4, and `-7 \ 2` is -3.
- `Mod` gives the remainder of that whole-number division. The operands are rounded the same
  way, and the result has the sign of the left operand: `-7 Mod 2` is -1, `7 Mod -2` is 1.
- `^` raises to a power and always gives a Double.

Dividing by zero, with `/`, `\` or `Mod`, is error 11, "Division by zero".

*Listing 7.2* (`examples/book/ch07-expressions/listing-07-02.bas`)

<!-- run -->
```basic
Dim a As Integer, b As Integer
a = 7: b = 2
Print a + b; a - b; a * b; a / b; a \ b; a Mod b
Print -7 \ 2; -7 Mod 2; 7 Mod -2
Print 7.5 \ 2; 6.5 \ 2; 8.5 Mod 3
Print 2 ^ 0.5
```

```output
 9  5  14  3.5  3  1 
-3 -1  1 
 4  3  2 
 1.4142135623731 
```

### The type of a result

When both operands have the same type, the result normally has that type too. When they
differ, the narrower one is widened first:

| Operands | Result of `+ - *` |
|---|---|
| Byte with Byte | Byte |
| Byte or Integer with Integer | Integer |
| Byte, Integer or Long with Long | Long |
| Byte or Integer with Single | Single |
| Long with Single, or anything numeric with Double | Double |
| Currency with Byte, Integer, Long or Currency | Currency |
| Currency with Single or Double | Double |
| Date plus or minus a number | Date |
| Date minus Date | Double (a number of days) |
| Boolean in arithmetic | as an Integer (-1 or 0) |

`\` and `Mod` give an Integer when both operands are Byte or Integer (a Byte for two Bytes),
and a Long otherwise. Remember that whole-number literals are Integers when they fit
([chapter 4](04-data.md#literals)).

*Listing 7.3* (`examples/book/ch07-expressions/listing-07-03.bas`)

<!-- run -->
```basic
Dim c As Currency
c = 2.5
Print TypeName(1 + 1); " "; TypeName(1 + 100000); " "; TypeName(1 + 1.5); " "; TypeName(1 / 2)
Print TypeName(c * 2); " "; TypeName(7 \ 2); " "; TypeName(7.5 \ 2); " "; TypeName(2 ^ 2)
Print TypeName(#1/2/2026# + 1); " "; TypeName(#1/2/2026# - #1/1/2026#); " "; TypeName(True + True)
```

```output
Integer Long Double Double
Currency Integer Long Double
Date Double Integer
```

### Overflow

Typed arithmetic never wraps round. A result that does not fit the result type is error 6,
"Overflow", and so is storing a value in a variable too small for it. With literals this is
easy to hit by accident, because `200 * 200` is Integer arithmetic:

*Listing 7.4* (`examples/book/ch07-expressions/listing-07-04.bas`)

<!-- run -->
```basic
Dim big As Long
On Error Resume Next
big = 200 * 200
Print "200 * 200:"; Err.Number; Err.Description
Err.Clear
big = 200& * 200
Print "200& * 200:"; big; Err.Number
big = CLng(200) * 200
Print "CLng(200) * 200:"; big
```

```output
200 * 200: 6 Overflow
200& * 200: 40000  0 
CLng(200) * 200: 40000 
```

Make one operand a Long (with `&`, `CLng` or a Long variable) and the multiplication is done
in Long. Single and Double results that would be infinite are error 6 too:

*Listing 7.5* (`examples/book/ch07-expressions/listing-07-05.bas`)

<!-- run -->
```basic
Dim d As Double, x As Double
x = 1E308
On Error Resume Next
d = x * 10
Print "x * 10:"; Err.Number; Err.Description
```

```output
x * 10: 6 Overflow
```

When every operand of a Single or Double calculation is a constant, Boing BASIC works the
result out while compiling, so the same overflow is found before the program runs:
`boing check` reports it as a compile error.

<!-- error: overflow (error 6) in a constant expression -->
```basic
Dim d As Double
d = 1E308 * 10
```

```text
huge.bas:2:11: error: overflow (error 6) in a constant expression
```

This applies to `*`, `/`, `+`, `-` and `^` with Single and Double constants, in a `Const` as
well as in an ordinary expression. Whole-number constants such as `200 * 200` are still
checked when the line runs, as in the listing above.

Variants are different: an Integer result in a Variant that does not fit becomes a Long, and
a Long becomes a Double, so Variant arithmetic does not overflow:

*Listing 7.6* (`examples/book/ch07-expressions/listing-07-06.bas`)

<!-- run -->
```basic
Dim v As Variant
v = 32767
v = v + 1
Print v; TypeName(v)
v = CLng(2147483647)
v = v + 1
Print v; TypeName(v)
```

```output
 32768 Long
 2147483648 Double
```

For bit-level work where you want wrap-round, use `And` masks, the shift functions `Shl`,
`ShrA` and `ShrL`, or `MulShr` and `MulDiv` ([chapter 9](09-builtins.md)).

## Joining strings: & and +

`&` joins two values as strings. A number is converted as by `CStr` (no leading space, and a
leading zero before a decimal point), a Boolean becomes `True` or `False`, a Date its printed
form, and `Null` or `Empty` become `""`.

`+` adds. It joins only when both operands are strings. With a string and a number it adds
them as numbers, which is error 13, "Type mismatch", if the string is not a number. Use `&`
for joining text, and `+` only for adding.

*Listing 7.7* (`examples/book/ch07-expressions/listing-07-07.bas`)

<!-- run -->
```basic
Dim n As Integer
n = 5
Print "n is " & n; " | "; "x" & 0.5; " | "; 1 & 2
Print "5" + "5"; " | "; "5" + 5; " | "; "5" & 5
On Error Resume Next
Print "a" + 1
Print "Error"; Err.Number; Err.Description
```

```output
n is 5 | x0.5 | 12
55 |  10  | 55
Error 13 Type mismatch
```

## Comparison

The comparison operators `=`, `<>`, `<`, `>`, `<=` and `>=` give `True` or `False`.

- **Numbers** compare by value, after converting to a common type.
- **Strings** compare character by character by character code (`Option Compare Binary`, the
  default), so upper case comes before lower case: `"Z" < "a"`. A string that is the start
  of another is less: `"ab" < "abc"`. Under `Option Compare Text`, case is ignored.
- **A string and a number** in typed code: the string is converted to a number (error 13 if it
  is not one). `1 < "2"` is True.
- **Dates** compare as their numbers, so a later date is greater.
- **Booleans** compare as numbers: `True` (-1) is less than `False` (0).

Variants compare by what they hold: two numbers numerically, two strings as strings, and a
number with a string by putting every number before every string. A comparison with `Null`
gives `Null`. `Empty` compares as 0 with a number and as `""` with a string.

*Listing 7.8* (`examples/book/ch07-expressions/listing-07-08.bas`)

<!-- run -->
```basic
Dim a As Variant, b As Variant
Print "abc" < "abd"; "Z" < "a"; "ab" < "abc"; 1 < "2"
a = 10: b = "9"
Print a < b; a + b
a = "10": b = "9"
Print a < b; a + b
a = Empty
Print a = 0; a = ""
Print IsNull(Null = Null)
```

```output
TrueTrueTrueTrue
True 19 
True109
TrueTrue
True
```

Records (user-defined types) and arrays cannot be compared.

### Like

`string Like pattern` tests a string against a pattern:

| In the pattern | Matches |
|---|---|
| `?` | any one character |
| `*` | any number of characters, including none |
| `#` | any one digit, 0 to 9 |
| `[abc]` | any one of the characters listed |
| `[a-z]` | any one character in the range |
| `[!a-z]` | any one character not in the list or range |
| any other character | itself |

To match `?`, `*`, `#` or `[` literally, put it in brackets: `"a*c" Like "a[*]c"`.
`Like` is case-sensitive, unless the module has `Option Compare Text`.

*Listing 7.9* (`examples/book/ch07-expressions/listing-07-09.bas`)

<!-- run -->
```basic
Print "Boing" Like "B*"; "Boing" Like "b*"; "A1200" Like "A####"; "A500" Like "A####"
Print "cat" Like "c?t"; "cot" Like "c[aeiu]t"; "cot" Like "c[!o]t"; "a*c" Like "a[*]c"
```

```output
TrueFalseTrueFalse
TrueFalseFalseTrue
```

### Is

`a Is b` is `True` when both object variables refer to the same object, and `x Is Nothing`
tests whether an object variable refers to any object. Both operands must be objects (or
Variants holding objects). `TypeOf x Is ClassName` tests an object's class; it is described with
classes in [chapter 11](11-classes.md).

## Logical and bitwise operators

`Not`, `And`, `Or`, `Xor`, `Eqv` and `Imp` work on Booleans and on whole numbers.

With Boolean operands, the result is a Boolean:

| `a` | `b` | `Not a` | `a And b` | `a Or b` | `a Xor b` | `a Eqv b` | `a Imp b` |
|---|---|---|---|---|---|---|---|
| True | True | False | True | True | False | True | True |
| True | False | False | False | True | True | False | False |
| False | True | True | False | True | True | False | True |
| False | False | True | False | False | False | True | True |

With whole numbers, they work on each bit, giving an Integer or a Long. This is how you test,
set and clear flags: `flags And 4` tests bit 2, `flags Or 4` sets it, and `flags And Not 4`
clears it. Because `True` is -1 (all bits set), `Not True` is `False` and comparisons combine
correctly with `And` and `Or`.

*Listing 7.10* (`examples/book/ch07-expressions/listing-07-10.bas`)

<!-- run -->
```basic
Print True And False; True Or False; True Xor True; Not False; False Imp True
Print 6 And 3; 6 Or 3; 6 Xor 3; Not 0; Not 5
Dim flags As Long
flags = 1 Or 4
Print (flags And 4) <> 0; flags And Not 4
```

```output
FalseTrueFalseTrueTrue
 2  7  5 -1 -6 
True 1 
```

There is no short-circuit evaluation: both operands of `And` and `Or` are always worked out,
even when the first already decides the result. If the second operand must not be evaluated
(because it would fail, or because it calls a function with side effects), use nested `If`
statements:

*Listing 7.11* (`examples/book/ch07-expressions/listing-07-11.bas`)

<!-- run -->
```basic
Function Check(ByVal name As String, ByVal result As Boolean) As Boolean
    Print "checking "; name
    Check = result
End Function

If Check("first", False) And Check("second", True) Then Print "both"
```

```output
checking first
checking second
```

With `Null`, the logical operators follow three-valued logic: `Null And False` is `False`,
`Null Or True` is `True`, and other combinations with `Null` give `Null`.

## Conversions

### Automatic conversion

Boing BASIC converts values when it needs to: when you assign a value to a variable of another
type, pass an argument to a parameter of another type, or mix types in an operator.

| From | To | What happens |
|---|---|---|
| a number with a fraction | Byte, Integer, Long | rounded to the nearest whole number, halves to even (2.5 -> 2, 3.5 -> 4) |
| a number | a smaller type | error 6 if it does not fit (300 into a Byte, 40000 into an Integer) |
| a number | String | as `CStr`: `1.5` -> `"1.5"`, `0.5` -> `"0.5"` |
| a String | a number | the string is read as a number (spaces around it are allowed, `&H` and `&O` forms too); error 13 if it is not a number |
| a String | Boolean | `"True"` / `"False"` (any case) or a number; error 13 otherwise |
| a number | Boolean | 0 is False, anything else True |
| Boolean | a number | True is -1, False is 0 |
| a number | Date | the number of days since 30 December 1899 |
| a String | Date | read as a date (month/day/year, year-month-day, times) |
| anything | Variant | the Variant holds it with its own type |
| `Null` | anything but Variant | error 94, "Invalid use of Null" |
| `Empty` | a number or String | 0 or `""` |

A user-defined type cannot be converted to anything, or stored in a Variant.

*Listing 7.12* (`examples/book/ch07-expressions/listing-07-12.bas`)

<!-- run -->
```basic
Dim i As Integer, s As String, ok As Boolean, d As Double
i = 2.5: Print i;
i = 3.5: Print i;
i = "42": Print i
s = 3.25: Print s
ok = "TRUE": Print ok
d = " 1.5e3 ": Print d
On Error Resume Next
i = "abc"
Print "Error"; Err.Number; Err.Description
```

```output
 2  4  42 
3.25
True
 1500 
Error 13 Type mismatch
```

### Conversion functions

The conversion functions convert explicitly. They take any value that can be converted, and
raise error 13 if it cannot be, or error 6 if it is out of range for the result type.

| Function | Result | Notes |
|---|---|---|
| `CBool(x)` | Boolean | 0 -> False, other numbers -> True; `"True"`, `"False"` |
| `CByte(x)` | Byte | rounds halves to even; 0 to 255 |
| `CInt(x)` | Integer | rounds halves to even; -32768 to 32767 |
| `CLng(x)` | Long | rounds halves to even |
| `CSng(x)` | Single | |
| `CDbl(x)` | Double | |
| `CCur(x)` | Currency | rounded to 4 decimal places |
| `CDec(x)` | Variant (Decimal) | up to 28 significant digits; Doubles convert with 15 digits, Singles with 7 |
| `CDate(x)` | Date | from a number or a date string |
| `CStr(x)` | String | numbers without a leading space; `Empty` -> `""` |
| `CVar(x)` | Variant | |

*Listing 7.13* (`examples/book/ch07-expressions/listing-07-13.bas`)

<!-- run -->
```basic
Print CInt(2.5); CInt(3.5); CInt(-2.5); CLng(1234567.5); CByte(254.4)
Print CBool(1); CBool(0); CBool("false")
Print CStr(12) & "|" & CStr(-3.5) & "|" & CStr(True)
Print CDbl("3.25") * 2; CLng("&HFF"); CInt(" 12 ")
Print CCur(12.345678); CDate("2026-03-04"); CDbl(#1/1/2000#)
Print CDec("79228162514264337593543950335")
Print TypeName(CVar(5)); " "; TypeName(CDec(1)); " "; TypeName(CSng(1))
```

```output
 2  4 -2  1234568  254 
TrueFalseFalse
12|-3.5|True
 6.5  255  12 
 12.3457 3/4/2026 36526 
 79228162514264337593543950335 
Integer Decimal Single
```

`CInt`, `CLng` and `CByte` round halves to the even number. To truncate instead, use `Int`
(rounds down) or `Fix` (rounds toward zero); `Round(x, places)` rounds to a number of
decimal places. These, and `Val`, `Str`, `Hex`, `Oct` and `Format`, which turn numbers into
text and back, are in [chapter 9](09-builtins.md).

*Listing 7.14* (`examples/book/ch07-expressions/listing-07-14.bas`)

<!-- run -->
```basic
Print Int(2.7); Int(-2.7); Fix(2.7); Fix(-2.7); Round(2.5); Round(3.14159, 2)
Print Val("12abc"); Val("abc"); Str(42) & "|" & CStr(42)
```

```output
 2 -3  2 -2  2  3.14 
 12  0  42|42
```

`Val` reads as much of a string as looks like a number and never fails, while `CDbl` and
the other conversions insist on a whole valid number. `Str` puts a space before a positive
number, `CStr` does not.

## Empty, Null and Nothing

These three special values are easy to confuse:

| Value | Belongs to | Means | Test with |
|---|---|---|---|
| `Empty` | Variant | not assigned yet; acts as 0 or `""` | `IsEmpty(v)` |
| `Null` | Variant | no valid value; spreads through expressions | `IsNull(v)` |
| `Nothing` | object variables | refers to no object | `obj Is Nothing` |

*Listing 7.15* (`examples/book/ch07-expressions/listing-07-15.bas`)

<!-- run -->
```basic
Dim v As Variant, o As Object
Print IsEmpty(v); v + 5; "[" & v & "]"
v = Null
Print IsNull(v); IsNull(v + 5); "[" & v & "]"
Print o Is Nothing
v = Empty
Print IsEmpty(v)
```

```output
True 5 []
TrueTrue[]
True
True
```

`Null` passed to a function that needs a real value (such as `Len`, `Left` or `CStr`) is
error 94, "Invalid use of Null". Assigning `Null` to a typed variable is error 94 too.
`Nothing` is assigned with `Set`: `Set o = Nothing`. Using an object variable that is
`Nothing` is error 91 ([chapter 11](11-classes.md)).

## Finding out types: TypeName and VarType

`TypeName(x)` returns the name of the type of a value, or for a Variant, of what it holds:
`"Integer"`, `"Long"`, `"Single"`, `"Double"`, `"Currency"`, `"Decimal"`, `"Date"`,
`"String"`, `"Boolean"`, `"Byte"`, `"Empty"`, `"Null"`, `"Error"` (a missing optional
argument), `"Nothing"`, a class name such as
`"Collection"`, or for an array the element type followed by `()`, such as `"Integer()"` or
`"Variant()"`.

`VarType(x)` returns a number for the type. Each has a constant:

| Value | Constant | Type |
|---|---|---|
| 0 | `vbEmpty` | Empty |
| 1 | `vbNull` | Null |
| 2 | `vbInteger` | Integer |
| 3 | `vbLong` | Long |
| 4 | `vbSingle` | Single |
| 5 | `vbDouble` | Double |
| 6 | `vbCurrency` | Currency |
| 7 | `vbDate` | Date |
| 8 | `vbString` | String |
| 9 | `vbObject` | an object, or `Nothing` |
| 10 | `vbError` | an error value (a missing optional argument) |
| 11 | `vbBoolean` | Boolean |
| 12 | `vbVariant` | Variant (only inside an array type) |
| 14 | `vbDecimal` | Decimal (a Variant made by `CDec`) |
| 17 | `vbByte` | Byte |
| 8192 + type | `vbArray` + type | an array: 8194 is an array of Integer, 8204 an array of Variant |

*Listing 7.16* (`examples/book/ch07-expressions/listing-07-16.bas`)

<!-- run -->
```basic
Dim nums(3) As Integer, v As Variant, c As New Collection
Print TypeName(nums); VarType(nums); VarType(nums) - vbArray
v = Array(1, 2)
Print TypeName(v); VarType(v)
v = 1.5@
Print TypeName(v); VarType(v)
Print TypeName(c); VarType(c); " "; TypeName(Nothing)
Print TypeName(CByte(1)); VarType(CByte(1)); " "; TypeName(#1/1/2026#); VarType(#1/1/2026#)
```

```output
Integer() 8194  2 
Variant() 8204 
Currency 6 
Collection 9  Nothing
Byte 17  Date 7 
```

The other inspection functions are `IsNumeric(x)` (can it be read as a number?),
`IsDate(x)`, `IsEmpty(v)`, `IsNull(v)`, `IsObject(v)`, `IsArray(v)` and `IsMissing(param)`;
they are listed in [chapter 9](09-builtins.md).

## Choosing between values: IIf and Choose

`IIf(condition, a, b)` returns `a` when the condition is true and `b` otherwise. Like any
function, it works out all its arguments first, so both `a` and `b` are evaluated.
`Choose(n, a, b, c, ...)` returns its `n`th value after `n`, or `Null` when there is none.

*Listing 7.17* (`examples/book/ch07-expressions/listing-07-17.bas`)

<!-- run -->
```basic
Dim n As Integer
n = 7
Print IIf(n Mod 2 = 0, "even", "odd"); " "; Choose(2, "one", "two", "three"); " "; IsNull(Choose(9, "x"))
```

```output
odd two True
```

## Summary

- Precedence runs `^`, negation, `* /`, `\`, `Mod`, `+ -`, `&`, comparisons, `Not`, `And`,
  `Or`, `Xor`, `Eqv`, `Imp`. Use parentheses when in doubt.
- Typed whole-number arithmetic raises error 6 on overflow; Variant arithmetic widens.
- Use `&` to join text and `+` to add numbers.
- `And` and `Or` are bitwise on numbers and never short-circuit.
- Assignments convert automatically, rounding halves to even; `CInt`, `CLng`, `CDbl`,
  `CStr` and the rest convert explicitly.
- `Empty`, `Null` and `Nothing` are different; test them with `IsEmpty`, `IsNull` and
  `Is Nothing`.

See also: [Program structure and data](04-data.md), [Control flow](06-control-flow.md),
[Errors and error handling](08-errors.md), [Built-in functions](09-builtins.md).
