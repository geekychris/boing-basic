# Appendix A: Keywords and statements

This appendix lists every keyword of Boing BASIC, every statement, and the words that have a
special meaning only inside a particular statement, one line each, with the chapter that
describes it. Keywords are reserved: you cannot use them as names of variables, procedures
or types (after a dot, as a member name, any word is allowed). Case never matters. Built-in
functions are listed in [appendix B](appendix-b-functions.md).

## Reserved keywords

| Keyword | Use | Chapter |
|---|---|---|
| `AddressOf` | `AddressOf Proc`: the address of a procedure, for AmigaOS callbacks | [17](17-amigaos.md) |
| `And` | logical and bitwise AND | [7](07-expressions.md#logical-and-bitwise-operators) |
| `As` | gives a type in `Dim`, parameters and `Function`; also in `Open ... As #n` and `Name a As b` | [4](04-data.md#declaring-variables) |
| `ByRef` | parameter passed by reference (the default) | [5](05-procedures.md#byval-and-byref) |
| `ByVal` | parameter passed by value | [5](05-procedures.md#byval-and-byref) |
| `Call` | `Call Proc(args)`: calls a Sub or Function | [5](05-procedures.md#sub-procedures) |
| `Case` | a branch of `Select Case`; `Case Else` | [6](06-control-flow.md#select-case) |
| `Close` | `Close [#n, ...]`: closes files | [10](10-files.md) |
| `Const` | declares a constant | [4](04-data.md#constants) |
| `Declare` | `Declare Sub/Function ... Lib`: an AmigaOS library function | [17](17-amigaos.md) |
| `Dim` | declares variables and arrays | [4](04-data.md#dim) |
| `Do` | `Do ... Loop` | [6](06-control-flow.md#do--loop) |
| `Each` | `For Each ... In` | [6](06-control-flow.md#for-each--next), [11](11-classes.md) |
| `Else` | the last branch of `If`; `Case Else` | [6](06-control-flow.md#if) |
| `ElseIf` | a further condition in a block `If` (one word: `Else If` is an `Else` holding a new `If`, with its own `End If`) | [6](06-control-flow.md#block-if) |
| `Empty` | the value of an unassigned Variant | [7](07-expressions.md#empty-null-and-nothing) |
| `End` | ends the program; with a word after it, ends a block (`End If`, `End Select`, `End Sub`, `End Function`, `End Property`, `End Type`, `End Enum`, `End With`) | [6](06-control-flow.md#end-and-stop) |
| `Enum` | `Enum ... End Enum`: an enumeration | [4](04-data.md#enumerations) |
| `Eqv` | logical equivalence | [7](07-expressions.md#logical-and-bitwise-operators) |
| `Erase` | empties arrays | [4](04-data.md#erase) |
| `Error` | `Error n` raises an error; `On Error`; the `Error$(n)` function | [8](08-errors.md) |
| `Event` | `Event Name(params)`: declares an event in a class | [11](11-classes.md) |
| `Exit` | `Exit For`, `Exit Do`, `Exit Sub`, `Exit Function`, `Exit Property` | [6](06-control-flow.md#leaving-early-exit) |
| `False` | the Boolean value 0 | [4](04-data.md#boolean) |
| `For` | `For ... To ... Step ... Next`; `For Each`; `Open ... For` mode | [6](06-control-flow.md#for--next) |
| `Friend` | procedure visibility in a class (treated as `Public`) | [11](11-classes.md) |
| `Function` | declares a Function procedure | [5](05-procedures.md#function-procedures) |
| `Get` | `Property Get`; `Get #n, rec, var` reads from a file | [5](05-procedures.md#property-procedures), [10](10-files.md) |
| `Global` | the same as `Public` at module level | [5](05-procedures.md#modules-and-scope) |
| `GoSub` | `GoSub label`; `On n GoSub` | [6](06-control-flow.md#gosub-and-return) |
| `GoTo` | `GoTo label`; `On n GoTo`; `On Error GoTo` | [6](06-control-flow.md#labels-and-goto) |
| `If` | `If ... Then ... Else`, single-line or block | [6](06-control-flow.md#if) |
| `Imp` | logical implication | [7](07-expressions.md#logical-and-bitwise-operators) |
| `Implements` | `Implements Interface` in a class | [11](11-classes.md) |
| `In` | `For Each x In collection` | [6](06-control-flow.md#for-each--next) |
| `Input` | `Input` from the console, `Input #n` from a file, `Line Input`, the `Input$(n, #f)` function, `Open ... For Input` | [10](10-files.md) |
| `Is` | object identity `a Is b`; `Case Is > 5`; `TypeOf x Is Class` | [7](07-expressions.md#is) |
| `Let` | optional word before an assignment; `Property Let` | [4](04-data.md#assignment), [5](05-procedures.md#property-procedures) |
| `Like` | pattern matching | [7](07-expressions.md#like) |
| `Loop` | ends a `Do` loop; `Loop While`, `Loop Until` | [6](06-control-flow.md#do--loop) |
| `LSet` | `LSet s = x`: copies into a string, left-aligned | [9](09-builtins.md) |
| `Me` | the current object in a class or form | [11](11-classes.md) |
| `Mod` | remainder | [7](07-expressions.md#arithmetic) |
| `New` | `New Class`, `Dim x As New Class`: creates an object | [11](11-classes.md) |
| `Next` | ends a `For` loop; `Resume Next`; `On Error Resume Next` | [6](06-control-flow.md#for--next) |
| `Not` | logical and bitwise NOT | [7](07-expressions.md#logical-and-bitwise-operators) |
| `Nothing` | the object reference to no object | [7](07-expressions.md#empty-null-and-nothing), [11](11-classes.md) |
| `Null` | the Variant value meaning "no valid value" | [7](07-expressions.md#empty-null-and-nothing) |
| `On` | `On Error GoTo label`, `On Error GoTo 0`, `On Error GoTo -1`, `On Error Resume Next`; `On n GoTo/GoSub` | [8](08-errors.md), [6](06-control-flow.md#on--goto-and-on--gosub) |
| `Open` | `Open path For mode As #n` | [10](10-files.md) |
| `Option` | `Option Explicit`, `Option Base`, `Option Compare`, `Option Private Module` | [4](04-data.md#option-statements) |
| `Optional` | an optional parameter | [5](05-procedures.md#optional-parameters) |
| `Or` | logical and bitwise OR | [7](07-expressions.md#logical-and-bitwise-operators) |
| `ParamArray` | a parameter that takes any number of arguments | [5](05-procedures.md#paramarray) |
| `Preserve` | `ReDim Preserve`: keeps the elements | [4](04-data.md#dynamic-arrays-and-redim) |
| `Print` | `Print` to the console, `Print #n` to a file | [10](10-files.md) |
| `Private` | visible in its own module or class only | [5](05-procedures.md#modules-and-scope) |
| `Property` | `Property Get/Let/Set`; `Exit Property` | [5](05-procedures.md#property-procedures) |
| `Public` | visible in every module | [5](05-procedures.md#modules-and-scope) |
| `RaiseEvent` | `RaiseEvent Name(args)`: fires an event of a class | [11](11-classes.md) |
| `ReDim` | sizes a dynamic array | [4](04-data.md#dynamic-arrays-and-redim) |
| `Resume` | `Resume`, `Resume Next`, `Resume label` in an error handler | [8](08-errors.md) |
| `Return` | returns from `GoSub` | [6](06-control-flow.md#gosub-and-return) |
| `RSet` | `RSet s = x`: copies into a string, right-aligned | [9](09-builtins.md) |
| `Select` | `Select Case ... End Select` | [6](06-control-flow.md#select-case) |
| `Set` | `Set obj = ...`: assigns an object reference; `Property Set` | [11](11-classes.md), [4](04-data.md#object) |
| `Static` | a local variable that keeps its value; `Static Sub/Function/Property` | [5](05-procedures.md#local-variables-and-static) |
| `Step` | the increment of a `For` loop | [6](06-control-flow.md#for--next) |
| `Stop` | prints `Stop` and ends the program | [6](06-control-flow.md#end-and-stop) |
| `Sub` | declares a Sub procedure; `Exit Sub`, `End Sub` | [5](05-procedures.md#sub-procedures) |
| `Then` | follows the condition of `If` and `ElseIf` | [6](06-control-flow.md#if) |
| `To` | array bounds `(1 To 10)`; `For i = 1 To n`; `Case 1 To 5` | [4](04-data.md#arrays), [6](06-control-flow.md) |
| `True` | the Boolean value -1 | [4](04-data.md#boolean) |
| `Type` | `Type ... End Type`: a user-defined type | [4](04-data.md#user-defined-types) |
| `TypeOf` | `TypeOf x Is Class`: tests an object's class | [11](11-classes.md) |
| `Until` | `Do Until`, `Loop Until` | [6](06-control-flow.md#do--loop) |
| `Wend` | ends a `While` loop | [6](06-control-flow.md#while--wend) |
| `While` | `While ... Wend`; `Do While`, `Loop While` | [6](06-control-flow.md#while--wend) |
| `With` | `With obj ... End With`: members of one object or record | [11](11-classes.md) |
| `WithEvents` | `Dim WithEvents x As Class`: handles an object's events | [11](11-classes.md) |
| `Write` | `Write #n, ...`: writes quoted, comma-separated values; `Access Write` | [10](10-files.md) |
| `Xor` | logical and bitwise exclusive OR | [7](07-expressions.md#logical-and-bitwise-operators) |

## Words special only in one statement

These are not reserved: they mean something only in the place shown, and you can use them as
names elsewhere.

| Word | Where | Chapter |
|---|---|---|
| `Rem` | at the start of a statement: a comment | [4](04-data.md#comments) |
| `#Include` | `#Include "file.bi"` at the start of a line: adds that file to the program as a module of its own (once) | [5](05-procedures.md#sharing-code-include-and-uses), [17](17-amigaos.md#the-ready-made-bindings) |
| `Explicit`, `Base`, `Compare`, `Binary`, `Text`, `Module` | after `Option` | [4](04-data.md#option-statements) |
| `DefBool`, `DefByte`, `DefInt`, `DefLng`, `DefCur`, `DefSng`, `DefDbl`, `DefDate`, `DefStr`, `DefObj`, `DefVar` | at the start of a line at module level: default types by first letter | [4](04-data.md#deftype-statements) |
| `Line` | `Line Input [#n,] var`: reads a whole line | [10](10-files.md) |
| `Debug` | `Debug.Print`: prints to the console | [10](10-files.md) |
| `Put` | `Put #n, [rec], var`: writes to a file | [10](10-files.md) |
| `Seek` | `Seek #n, pos`: moves in a file (also the `Seek(n)` function) | [10](10-files.md) |
| `Name` | `Name old As new`: renames a file | [10](10-files.md) |
| `Output`, `Append`, `Binary`, `Random` | `Open ... For` mode | [10](10-files.md) |
| `Access`, `Read`, `Shared`, `Lock`, `Len` | in `Open` (`Access Read Write`, `Len = reclen`) | [10](10-files.md) |
| `Lock`, `Unlock` | `Lock #n [, rec [To rec]]` as a statement: accepted and checked, locks nothing | [10](10-files.md#opening-and-closing) |
| `Width` | `Width #n, columns`: lines written to a file wrap at that column | [10](10-files.md#writing-and-reading-text) |
| `Spc`, `Tab` | in a `Print` list | [10](10-files.md) |
| `Lib`, `Alias`, `Interface`, `Version` | in `Declare` | [17](17-amigaos.md) |
| `Attribute`, `VERSION`, `BEGIN` | header lines of class and form files saved by other tools; skipped | [11](11-classes.md) |
| `Mid`, `Mid$` | `Mid$(s, start[, len]) = x` as a statement: replaces characters | [9](09-builtins.md) |

## Type names

| Name | Chapter |
|---|---|
| `Boolean`, `Byte`, `Integer`, `Long`, `Single`, `Double`, `Currency`, `Date`, `String`, `String * n`, `Variant`, `Object` | [4](04-data.md#data-types) |
| `Any` (parameters of `Declare` only) | [17](17-amigaos.md) |
| `Collection` | [11](11-classes.md) |
| `Canvas` | [14](14-graphics.md) |
| `Engine3D` | [15](15-engine3d.md) |
| `Audio` | [16](16-audio.md) |

## Operators and punctuation

| Symbol | Meaning | Chapter |
|---|---|---|
| `+ - * / \ ^` | arithmetic | [7](07-expressions.md#arithmetic) |
| `&` | string concatenation; `&H` and `&O` number prefixes; the Long type suffix | [7](07-expressions.md#joining-strings--and-), [4](04-data.md#literals) |
| `= <> >< < > <= >=` | comparison (`=` is also assignment) | [7](07-expressions.md#comparison) |
| `:=` | names an argument: `Proc x:=1` | [5](05-procedures.md#named-arguments) |
| `:` | separates statements; ends a label | [4](04-data.md#lines-and-statements) |
| `_` | at the end of a line after a space: continues the statement | [4](04-data.md#lines-and-statements) |
| `'` | comment | [4](04-data.md#comments) |
| `" "` | string literal | [4](04-data.md#literals) |
| `# #` | date literal | [4](04-data.md#literals) |
| `#` | before a file number (`#1`); the Double type suffix | [10](10-files.md), [4](04-data.md#type-suffixes-on-names) |
| `% & ! # @ $` | type suffixes | [4](04-data.md#type-suffixes-on-names) |
| `.` | member access; inside `With`, a member of the `With` object | [11](11-classes.md) |
| `!` | `collection!key`, the same as `collection("key")` | [11](11-classes.md) |
| `;` `,` | in `Print`: no space, or move to the next 14-column zone | [10](10-files.md) |

## Built-in statements

These built-in procedures are written like statements (`Kill "T:old"`). Their arguments and
details are in [appendix B](appendix-b-functions.md).

| Statement | Use | Chapter |
|---|---|---|
| `Randomize [seed]` | starts a new random number sequence | [9](09-builtins.md) |
| `Beep` | sounds the system beep (on AmigaOS, the display beep) | [9](09-builtins.md) |
| `Sleep ms` | waits a number of milliseconds | [9](09-builtins.md) |
| `Kill`, `MkDir`, `RmDir`, `ChDir`, `FileCopy`, `SetAttr` | files and directories | [10](10-files.md) |
| `Reset` | closes every open file | [10](10-files.md#opening-and-closing) |
| `SaveSetting`, `UseSetting`, `DeleteSetting` | program settings | [10](10-files.md) |
| `Load`, `Unload` | open and close forms | [12](12-forms.md) |
| `PokeB`, `PokeW`, `PokeL`, `FreeMem`, `FreeTagList` | memory and pointers | [17](17-amigaos.md) |

## Not supported

There is no conditional compilation (`#If`), no `Decimal` variable type (use
`CDec` and a Variant, [chapter 4](04-data.md#decimal)), no `Exit While` (use `Exit Do`), and
no statement to continue with the next pass of a loop.
