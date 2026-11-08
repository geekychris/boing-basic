# Boing BASIC language reference

Boing BASIC is Visual Basic 6 as far as the language goes: the same keywords, types,
conversions and run-time errors. This page lists what is implemented and where Boing BASIC
differs. Programs run in the VM (`boing run`) or compile to C (`boing build`), and the two give
the same output. The test suite checks every feature on both.

## Programs and modules

- A program is one `.bas` file, or a project `.bbp` listing modules (`Module=`), class modules
  (`Class=`) and forms (`Form=x.afg`, code-behind `x.bas`). See DESIGN.md for the keys.
- Startup: statements at module level in the first (startup) module run as the main program.
  If there are none, `Sub Main` runs. VB itself needs `Sub Main`; the module-level statements are
  an extension for scripts, as in QBasic. A `Dim` among them is a module-level variable.
- `Option Explicit`, `Option Base 0|1`, `Option Compare Binary|Text` apply per module.
- VB class files with `VERSION`/`BEGIN`…`END`/`Attribute` headers are accepted; the headers are
  ignored.

## Lexical rules

- Keywords and names are case-insensitive. Comments start with `'` or `Rem`. A ` _` at the end
  of a line continues it. `:` separates statements.
- Line numbers and `label:` at the start of a line are labels.
- Literals: `123` (Integer if it fits, else Long, else Double), `123&`, `&HFF`, `&O17`, `&HFFFF`
  (= -1, Integer), `&HFFFF&` (= 65535), `1.5`, `1E10`, `1.5!` `2#` `3@`,
  `"text with ""quotes"""`, `#1/2/2000#`, `#2000-01-02#`, `#13:45:00#`, `#1:30 PM#`.
- Type suffixes `% & ! # @ $` on names; `Left$` and friends.

## Types

| Type | Size | Notes |
|---|---|---|
| `Boolean` | 16 bit | True = -1 |
| `Byte` | 8 bit | 0..255 |
| `Integer` | 16 bit | overflow → error 6 |
| `Long` | 32 bit | |
| `Single`, `Double` | IEEE | inf/NaN results → error 6 |
| `Currency` | 64 bit fixed point, 4 decimals | |
| `Date` | Double | days since 30 Dec 1899 |
| `String` | | variable length, 8 bit; `String * n` fixed length |
| `Variant` | | Empty, Null, any type or array; arithmetic widens on overflow |
| `Object`, class names, `Collection` | | references, `Nothing` |
| `Type … End Type` | | user types, nested types, fixed-array fields, `String * n` fields |
| `Enum … End Enum` | Long | members are constants (`Name` or `Enum.Name`) |

Declarations: `Dim`, `Private`, `Public`, `Global`, `Static` (in procedures, or
`Static Sub`), `Const`, `ReDim [Preserve]` (declares a local dynamic array if the name is new),
`Erase`. Arrays: `Dim a(10)`, `Dim a(1 To 5, 0 To 3)`, dynamic `Dim a()` + `ReDim`, up to 8
dimensions, column-major like VB. Fixed arrays need constant bounds. `ReDim Preserve` can change
only the last dimension. Assigning an array copies it (`a = b`). Functions can return arrays
(`Function F() As Long()`).

Implicit declaration without `Option Explicit`: an unknown name becomes a local Variant, or
the suffix's type.

`DefInt`, `DefLng`, `DefSng`, `DefDbl`, `DefCur`, `DefStr`, `DefBool`, `DefByte`, `DefDate`,
`DefObj`, `DefVar` with letter ranges (`DefInt I-N, X`) at module level set the type of
everything in that module declared without `As` or a suffix, by its first letter: variables
(also implicit ones), parameters and Function / Property Get results.

## Expressions

Operator precedence as VB: `^`, unary `-`, `* /`, `\`, `Mod`, `+ -`, `&`,
`= <> < > <= >= Like Is`, `Not`, `And`, `Or`, `Xor`, `Eqv`, `Imp`.

- `+` on two Strings concatenates; String + number is a numeric addition (error 13 if the
  string is not numeric).
- `/` gives a Double (Single for Single operands), `\` and `Mod` round their operands
  (banker's rounding) to Integer/Long.
- Integer results that overflow raise error 6. In Variants they widen (Integer → Long →
  Double) as in VB.
- Comparisons of typed values convert to a common type. Variant comparisons follow VB: numbers
  compare numerically, strings as strings, a number is less than a string, and Null compares
  to Null.
- `Like` with `? * # [a-z] [!a-z]`; `Option Compare Text` makes it, `StrComp`, `InStr` and
  string comparisons case-insensitive.
- Logical operators are bitwise on integers; Boolean operands give a Boolean. Null
  propagates through Variant operators (`Null And False` = False).
- `Is` compares object references; `TypeOf x Is Class` (also for interfaces).

## Statements

`If … Then … ElseIf … Else … End If` and the single-line `If c Then a: b Else c`,
`Select Case` (`Case 1, 3 To 5, Is > 10, Else`), `For … To … Step … Next [var, var]`,
`For Each … In … Next` (arrays, Collections, Variants holding either), `Do [While|Until] … Loop
[While|Until]`, `While … Wend`, `Exit For|Do|Sub|Function|Property`, `GoTo`, `GoSub … Return`,
`On n GoTo|GoSub a, b`, `With … End With` (objects and UDT variables, nested), `Call`,
`End`, `Stop`, `Mid$(s, start[, len]) = x`, `LSet`/`RSet`, `Randomize`, `Beep`, `Kill`,
`MkDir`, `RmDir`, `ChDir`, `FileCopy`, `Name a As b`, `Error n`.

Loop counters, limits and steps follow VB: the limit and step are evaluated once, and the
counter ends at the first value past the limit.

## Procedures

`Sub`, `Function`, `Property Get|Let|Set` in modules and classes; `Public`/`Private`/`Friend`.

- Parameters are `ByRef` by default. A ByRef argument must be a variable of exactly the
  parameter's type (VB's "ByRef argument type mismatch" otherwise). Expressions and
  parenthesised arguments `F (x)` pass a copy.
- `Optional` (with or without a default; `IsMissing` for Variants), `ParamArray args()`,
  named arguments `F(x:=1)`.
- Inside a function its name is the return value. `F(…)` with arguments is a recursive call.
- Calling a Sub: `Foo a, b`, `Call Foo(a, b)`, or `Foo (a)` (a passed by value).

## Errors

`On Error GoTo label`, `On Error Resume Next`, `On Error GoTo 0`, `Resume`, `Resume Next`,
`Resume label`, `Err.Number/.Description/.Source/.Raise n[, source[, desc]]/.Clear`,
`Error n`, `Erl` (the source line). The error numbers and messages are VB's (6 Overflow,
9 Subscript out of range, 11 Division by zero, 13 Type mismatch, 52/53/54/62… for files,
91 Object variable not set, 438 Object doesn't support this property or method, …).
`vbObjectError` is -2147221504. An unhandled error prints `file:line: runtime error n: message`
on stderr and exits with code 20. Errors propagate to the caller's handler. An error inside a
handler goes to the next handler up. `Exit Sub/Function` in a handler clears `Err`.
Procedures unwound by an error release their locals (objects' `Class_Terminate` runs) in
both back ends.

## Classes (`.cls`)

- Instance variables (`Private`/`Public` – public ones are properties), methods, `Property
  Get/Let/Set`, `Class_Initialize`, `Class_Terminate` (runs when the last reference goes away),
  `Me`.
- `New`, `Dim x As New C` (as in VB, the object is created when `x` is first used, also
  after `Set x = Nothing`; so `x Is Nothing` is always False), `Set`, `Nothing`, `Is`,
  `TypeOf`, `TypeName`.
- Variables typed with a class are early bound (direct calls). `Object` and `Variant` are late
  bound: members are found by name at run time. Both work on BASIC classes, `Collection` and
  runtime objects such as form controls.
- `Implements I`: the class provides `I_Member` procedures. Calls through an `I` variable
  dispatch to the object's implementation. Public variables in an interface class are not
  supported (use properties).
- Events: `Public Event Changed(ByVal x As Long, Cancel As Boolean)`, `RaiseEvent
  Changed(1, c)`, and in a class or module `Dim WithEvents src As C` with handlers named
  `src_Changed`. ByRef event arguments can be changed by the handler. (VB allows `WithEvents`
  only in class and form modules; Boing BASIC also allows it in standard modules.)
- Default members for late binding: `Item` or `Value`. `x(1)` on an object calls the default
  member; `col!key` is `col("key")`.

`Collection`: `Add item[, key][, before][, after]`, `Item(index|key)` (default), `Count`,
`Remove index|key`, `For Each`. Keys are case-insensitive. Error 5 for a missing key, 457 for
a duplicate one.

## Built-in functions

Strings: `Len Left Right Mid InStr InStrRev LCase UCase Trim LTrim RTrim Space String Replace
Split Join StrComp StrReverse Chr ChrW Asc AscW Val Str Hex Oct Format` (with `$` forms).

Maths: `Abs Sgn Int Fix Sqr Sin Cos Tan Atn Log Exp Rnd Randomize Round`. `Rnd` and
`Randomize` use VB's own generator, so `Rnd` sequences match VB6.

Conversion: `CInt CLng CSng CDbl CCur CStr CBool CByte CDate CVar CDec` (CDec gives a Double).
`CInt`/`CLng`/`CByte` and `Round` use banker's rounding.

Inspection: `IsNumeric IsDate IsEmpty IsNull IsObject IsArray IsMissing TypeName VarType
LBound UBound Array IIf Choose`.

Date/time: `Now Date Time Timer DateSerial TimeSerial DateValue TimeValue DateAdd DateDiff
DatePart Year Month Day Hour Minute Second Weekday MonthName WeekdayName`. Dates print and
convert in US style (`1/2/2003 4:05:06 PM`) and parse `m/d/y`, `y-m-d`, times with AM/PM.

`Format`: named formats (`General Number, Currency, Fixed, Standard, Percent, Scientific,
Yes/No, True/False, On/Off, General Date, Long/Medium/Short Date, Long/Medium/Short Time`),
numeric patterns (`0 # . , % E+ E-`, literals, `"text"`, `\c`, sections `pos;neg;zero`),
date patterns (`d dd ddd dddd ddddd dddddd w ww m mm mmm mmmm q y yy yyyy h hh n nn s ss
ttttt AM/PM am/pm A/P`), string patterns (`@ & < > !`).

Environment: `Command Environ Shell DoEvents MsgBox InputBox RGB Sleep` (`Sleep` takes
milliseconds; it is not a VB built-in).

Constants: `vbCrLf vbNewLine vbCr vbLf vbTab vbNullString vbNullChar`, `vbOK… vbNo`,
`vbOKOnly … vbYesNo`, `vbCritical … vbInformation`, `vbBinaryCompare vbTextCompare`,
`vbEmpty … vbArray` (VarType), `vbSunday … vbSaturday`, `vbDirectory` etc., `vbObjectError`,
colours, key codes. `vbNewLine` is a single LF (AmigaOS and Unix convention).

## Console and files

- `Print [#n,] items` with `;` (no space) and `,` (next 14-column zone), `Spc(n)`, `Tab(n)`,
  a trailing `;` or `,` keeps the line. Numbers print with a leading space (or `-`) and a
  trailing space, and without a leading zero (`.5`), as in VB. `Debug.Print` writes to the
  console.
- `Input ["prompt";] a, b` / `Input #n, …` (comma-separated fields, quoted strings),
  `Line Input`, `Input$(n, #f)`, `Write #n, …` (quoted strings, `#TRUE#`, `#NULL#`).
- `Open path For Input|Output|Append|Binary|Random [Access …] [Lock …] As #n [Len = r]`,
  `Close [#n, …]`, `Get`/`Put #n, [rec], var` (scalars, strings, UDTs and arrays; little-endian
  like VB files), `Seek #n, pos` / `Seek(n)`, `EOF LOF Loc FreeFile FileLen Dir Kill Name MkDir
  RmDir ChDir CurDir FileCopy`.
- `MsgBox` and `InputBox` prompt on the console on the host (`(y/n)` for vbYesNo). On AmigaOS
  they are requesters.

## Declare

```basic
Declare Function DisplayBeep Lib "intuition.library" Alias "#15" (ByVal scr As Long) As Long
Declare Sub Delay Lib "dos.library" Version 50 (ByVal ticks As Long)
```

`Lib "x.library"`, optional `Alias` (function name, or `"#n"` for the interface slot),
`Interface "main"` (default) and `Version n`. Arguments become 32-bit words: numbers by value,
`ByVal String` as a pointer to the text, `ByRef` as the variable's address. The call glue is
OS4's (see os4.md and the generated `bindings/*.bi`). On the host every Declare'd call raises
error 48/453.

## Not implemented (yet)

- `Decimal`; `CDec` returns a Double.
- `AddressOf`; `Friend` is treated as `Public`.
- Late-bound calls pass arguments by value (no ByRef through `Object`).
