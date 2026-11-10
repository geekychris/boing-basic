# Appendix B: Built-in functions

This appendix lists every built-in function and built-in statement of Boing BASIC in
alphabetical order, with its arguments, what it does in one line, and the chapter that describes
it. Arguments in square brackets are optional. A `$` after a name in the first column means the
function can also be written with `$` (`Left$`), which gives the same String.

Keywords and statements that are part of the language itself (`Dim`, `If`, `For`, `Open`,
`Print`, `On Error`...) are listed in [Appendix A](appendix-a-keywords.md). Members of the
runtime's objects (Canvas, Engine3D, Audio, form controls) are in their chapters.

The chapters referred to are: 04 [Data](04-data.md), 05 [Procedures](05-procedures.md),
07 [Expressions](07-expressions.md), 08 [Errors](08-errors.md),
09 [Built-in functions](09-builtins.md), 10 [Files and the system](10-files.md),
11 [Classes](11-classes.md), 12 [Forms](12-forms.md),
13 [Menus and dialogs](13-menus-dialogs.md), 14 [Graphics](14-graphics.md),
15 [Engine3D](15-engine3d.md), 16 [Audio](16-audio.md), 17 [AmigaOS](17-amigaos.md),
18 [The desktop](18-desktop.md).

| Syntax | What it does | Chapter |
|---|---|---|
| `Abs(x)` | `x` without its sign | [09](09-builtins.md#arithmetic-functions) |
| `AllocMem(size [, clear])` | allocates `size` bytes of memory (cleared to 0 if `clear` is True) and returns its address | [17](17-amigaos.md) |
| `App.CloseScreen` | closes the program's own screen if no window is open on it; `True` when it is closed (AmigaOS) | [18](18-desktop.md#screens) |
| `App.EXEName` | the program's name without directory or `.bas` | [10](10-files.md#the-app-object) |
| `App.OpenScreen modeid [, width, height, depth [, title]]` | statement: opens the program's own screen (a `ScreenModeID`, 0 = the Workbench's mode); forms loaded afterwards open on it (AmigaOS) | [18](18-desktop.md#screens) |
| `App.Path` | the program's directory | [10](10-files.md#files-beside-the-program-apppath) |
| `App.Title` | the program's title (`Title=`, `Name=` or the program's name); can be assigned | [10](10-files.md#the-app-object) |
| `Array(v1, v2, ...)` | a Variant holding an array of the values, from index 0 | [09](09-builtins.md#inspecting-values) |
| `Asc(s)` | the character code (0-255) of the first character of `s` | [09](09-builtins.md#characters-and-character-codes) |
| `AscW(s)` | the same as `Asc` | [09](09-builtins.md#characters-and-character-codes) |
| `Atn(x)` | the arctangent of `x`, in radians | [09](09-builtins.md#arithmetic-functions) |
| `Beep` | statement: flashes the screen (AmigaOS) or rings the terminal bell (host) | [09](09-builtins.md#the-system-and-the-program) |
| `CBool(x)` | converts to Boolean | [07](07-expressions.md) |
| `CByte(x)` | converts to Byte (0-255, rounding halves to even) | [07](07-expressions.md) |
| `CCur(x)` | converts to Currency | [07](07-expressions.md) |
| `CDate(x)` | converts to Date (also from strings such as `"2024-03-09"`) | [07](07-expressions.md), [09](09-builtins.md#dates-from-strings) |
| `CDbl(x)` | converts to Double | [07](07-expressions.md) |
| `CDec(x)` | converts to a Variant holding a Decimal | [07](07-expressions.md) |
| `ChDir path` | statement: changes the current directory | [10](10-files.md#working-with-files-and-directories) |
| `Choose(n, v1, v2, ...)` | the `n`th value (from 1), or Null | [09](09-builtins.md#choosing-a-value-iif-and-choose) |
| `Chr$(code)` | the character with code 0-255 | [09](09-builtins.md#characters-and-character-codes) |
| `ChrW$(code)` | the same as `Chr` | [09](09-builtins.md#characters-and-character-codes) |
| `CInt(x)` | converts to Integer (rounding halves to even) | [07](07-expressions.md) |
| `Clipboard.Clear` | statement: empties the clipboard | [13](13-menus-dialogs.md) |
| `Clipboard.GetText[(format)]` | the text on the clipboard (`format` is accepted and ignored) | [13](13-menus-dialogs.md) |
| `Clipboard.SetText text [, format]` | statement: puts text on the clipboard | [13](13-menus-dialogs.md) |
| `CLng(x)` | converts to Long (rounding halves to even) | [07](07-expressions.md) |
| `Command$` | the program's command-line arguments | [10](10-files.md#command) |
| `Cos(a)` | the cosine of an angle in radians | [09](09-builtins.md#arithmetic-functions) |
| `CreateObject(class)` | a runtime object: `"Boing.Canvas"`, `"Boing.Engine3D"`, `"Boing.Audio"`, `"Boing.CommonDialog"` | [14](14-graphics.md), [15](15-engine3d.md), [16](16-audio.md), [13](13-menus-dialogs.md) |
| `CSng(x)` | converts to Single | [07](07-expressions.md) |
| `CStr(x)` | converts to String | [07](07-expressions.md) |
| `CurDir$` | the current directory | [10](10-files.md#working-with-files-and-directories) |
| `CVar(x)` | converts to Variant | [07](07-expressions.md) |
| `CVDate(x)` | the same as `CDate` | [07](07-expressions.md) |
| `Date` | today's date | [09](09-builtins.md#the-current-date-and-time) |
| `DateAdd(interval, n, date)` | `date` plus `n` intervals (`"yyyy" "q" "m" "y" "d" "w" "ww" "h" "n" "s"`) | [09](09-builtins.md#date-arithmetic-dateadd-datediff-datepart) |
| `DateDiff(interval, d1, d2)` | the number of interval boundaries from `d1` to `d2` | [09](09-builtins.md#date-arithmetic-dateadd-datediff-datepart) |
| `DatePart(interval, date)` | one part of a date (year, quarter, week...) | [09](09-builtins.md#date-arithmetic-dateadd-datediff-datepart) |
| `DateSerial(y, m, d)` | the Date for a year, month and day | [09](09-builtins.md#building-and-taking-apart-dates) |
| `DateValue(x)` | the date part of a Date or date string | [09](09-builtins.md#building-and-taking-apart-dates) |
| `Day(d)` | the day of the month, 1-31 | [09](09-builtins.md#building-and-taking-apart-dates) |
| `DeleteSetting app [, section [, key]]` | statement: deletes saved settings | [10](10-files.md#settings-savesetting-and-getsetting) |
| `Dir$([pattern [, attributes]])` | the first (with a pattern) or next file name that matches; `""` when no more | [10](10-files.md#listing-a-directory-with-dir) |
| `DoEvents` | lets the program handle window and timer events; returns 0 | [09](09-builtins.md#the-system-and-the-program), [12](12-forms.md) |
| `Environ$(name)` | the value of an environment variable | [10](10-files.md#environ) |
| `EOF(n)` | True at the end of file `n` | [10](10-files.md#writing-and-reading-text) |
| `Erl` | the source line of the last error | [08](08-errors.md#the-err-object) |
| `Err.Clear` | clears the error state | [08](08-errors.md#the-err-object) |
| `Err.Description` | the message of the last error | [08](08-errors.md#the-err-object) |
| `Err.Number` | the number of the last error (also `Err` alone) | [08](08-errors.md#the-err-object) |
| `Err.Raise n [, source [, description]]` | raises error `n` | [08](08-errors.md#raising-your-own-errors) |
| `Err.Source` | where the last error came from | [08](08-errors.md#the-err-object) |
| `Error$([n])` | the message of error `n`, or of the current error | [08](08-errors.md#the-err-object) |
| `Exp(x)` | e to the power `x` | [09](09-builtins.md#arithmetic-functions) |
| `FileCopy source, dest` | statement: copies a file | [10](10-files.md#working-with-files-and-directories) |
| `FileLen(path)` | the size of a file in bytes | [10](10-files.md#working-with-files-and-directories) |
| `Fix(x)` | `x` without its fraction (towards zero) | [09](09-builtins.md#arithmetic-functions) |
| `Format$(x [, pattern])` | `x` as text laid out by a named format or a pattern | [09](09-builtins.md#format) |
| `FreeFile` | the lowest unused file number (1-255) | [10](10-files.md#opening-and-closing) |
| `FreeMem address` | statement: frees memory from `AllocMem` | [17](17-amigaos.md) |
| `FreeTagList address` | statement: frees a tag list from `TagList` | [17](17-amigaos.md) |
| `GetSetting(app, section, key [, default])` | a saved setting | [10](10-files.md#settings-savesetting-and-getsetting) |
| `Hex$(x)` | `x` in hexadecimal | [09](09-builtins.md#numbers-to-strings-and-back) |
| `Hour(d)` | the hour, 0-23 | [09](09-builtins.md#building-and-taking-apart-dates) |
| `IIf(condition, a, b)` | `a` if the condition is true, else `b` (both are worked out) | [09](09-builtins.md#choosing-a-value-iif-and-choose) |
| `Input$(n, #f)` | reads `n` characters from file `f` | [10](10-files.md#reading-characters-input) |
| `InputBox$(prompt [, title [, default]])` | asks the user for a line of text | [13](13-menus-dialogs.md) |
| `InStr([start,] s, find [, compare])` | the position of `find` in `s`, or 0 | [09](09-builtins.md#searching) |
| `InStrRev(s, find [, start [, compare]])` | the position of the last `find` in `s`, or 0 | [09](09-builtins.md#searching) |
| `Int(x)` | the largest whole number not above `x` | [09](09-builtins.md#arithmetic-functions) |
| `IsArray(x)` | True if `x` is an array | [09](09-builtins.md#inspecting-values) |
| `IsDate(x)` | True if `x` is or converts to a Date | [09](09-builtins.md#inspecting-values) |
| `IsEmpty(x)` | True if the Variant `x` is Empty | [09](09-builtins.md#inspecting-values) |
| `IsMissing(x)` | True if the Optional Variant parameter `x` was not passed | [05](05-procedures.md) |
| `IsNull(x)` | True if `x` is Null | [09](09-builtins.md#inspecting-values) |
| `IsNumeric(x)` | True if `x` is or converts to a number | [09](09-builtins.md#inspecting-values) |
| `IsObject(x)` | True if `x` holds an object reference | [09](09-builtins.md#inspecting-values) |
| `Join(array [, delimiter])` | the elements joined into one string | [09](09-builtins.md#splitting-and-joining) |
| `Kill pattern` | statement: deletes files | [10](10-files.md#files-and-directories) |
| `LBound(array [, dimension])` | the lowest index of an array | [04](04-data.md), [09](09-builtins.md#inspecting-values) |
| `LCase$(s)` | `s` in small letters | [09](09-builtins.md#changing-case-trimming-building) |
| `Left$(s, n)` | the first `n` characters | [09](09-builtins.md#length-and-pieces) |
| `Len(x)` | the length of a string, or the size in bytes of a variable | [09](09-builtins.md#length-and-pieces) |
| `Load form` | statement: loads a form without showing it | [12](12-forms.md) |
| `Loc(n)` | the position in file `n` (bytes or records before it) | [10](10-files.md#binary-files-get-and-put) |
| `LOF(n)` | the length of file `n` in bytes | [10](10-files.md#binary-files-get-and-put) |
| `Log(x)` | the natural logarithm | [09](09-builtins.md#arithmetic-functions) |
| `LSet var = s` | statement: `s` left-aligned in the String variable, keeping its length | [09](09-builtins.md#fixed-width-fields-lset-and-rset) |
| `LTrim$(s)` | `s` without leading spaces | [09](09-builtins.md#changing-case-trimming-building) |
| `Mid$(s, start [, length])` | part of a string | [09](09-builtins.md#length-and-pieces) |
| `Mid$(var, start [, length]) = s` | statement: replaces characters inside a String variable | [09](09-builtins.md#changing-part-of-a-string-the-mid-statement) |
| `Minute(d)` | the minute, 0-59 | [09](09-builtins.md#building-and-taking-apart-dates) |
| `MkDir path` | statement: makes a directory | [10](10-files.md#files-and-directories) |
| `Month(d)` | the month, 1-12 | [09](09-builtins.md#building-and-taking-apart-dates) |
| `MonthName(m [, abbreviate])` | "January"... or "Jan"... | [09](09-builtins.md#building-and-taking-apart-dates) |
| `MsgBox(prompt [, buttons [, title]])` | shows a message (as a statement or a function returning the button pressed) | [13](13-menus-dialogs.md) |
| `MulDiv(a, b, c)` | `a * b \ c` with a 64-bit product | [09](09-builtins.md#bit-shifts-and-fixed-point-arithmetic) |
| `MulShr(a, b, k)` | `(a * b)` shifted right `k` bits, with a 64-bit product | [09](09-builtins.md#bit-shifts-and-fixed-point-arithmetic) |
| `Name old As new` | statement: renames or moves a file | [10](10-files.md#files-and-directories) |
| `Now` | the current date and time | [09](09-builtins.md#the-current-date-and-time) |
| `ObjPtr(object)` | the address of an object | [17](17-amigaos.md) |
| `Oct$(x)` | `x` in octal | [09](09-builtins.md#numbers-to-strings-and-back) |
| `PeekB(address)` | the unsigned byte at an address | [17](17-amigaos.md) |
| `PeekL(address)` | the signed 32-bit value at an address | [17](17-amigaos.md) |
| `PeekS(address [, maxlen])` | the C string at an address | [17](17-amigaos.md) |
| `PeekW(address)` | the unsigned 16-bit value at an address | [17](17-amigaos.md) |
| `PokeB address, value` | statement: writes a byte to memory | [17](17-amigaos.md) |
| `PokeL address, value` | statement: writes a 32-bit value to memory | [17](17-amigaos.md) |
| `PokeW address, value` | statement: writes a 16-bit value to memory | [17](17-amigaos.md) |
| `Randomize [seed]` | statement: starts a new random sequence (from the clock, or from `seed`) | [09](09-builtins.md#random-numbers) |
| `Replace(s, find, with [, start [, count [, compare]]])` | `s` with `find` replaced by `with` | [09](09-builtins.md#changing-case-trimming-building) |
| `RGB(red, green, blue)` | a colour value | [09](09-builtins.md#the-system-and-the-program), [14](14-graphics.md) |
| `Right$(s, n)` | the last `n` characters | [09](09-builtins.md#length-and-pieces) |
| `RmDir path` | statement: removes an empty directory | [10](10-files.md#files-and-directories) |
| `Rnd[(x)]` | a random Single from 0 up to 1 | [09](09-builtins.md#random-numbers) |
| `Round(x [, decimals])` | `x` rounded (halves to even) | [09](09-builtins.md#arithmetic-functions) |
| `RSet var = s` | statement: `s` right-aligned in the String variable, keeping its length | [09](09-builtins.md#fixed-width-fields-lset-and-rset) |
| `RTrim$(s)` | `s` without trailing spaces | [09](09-builtins.md#changing-case-trimming-building) |
| `SaveSetting app, section, key, value` | statement: saves a setting | [10](10-files.md#settings-savesetting-and-getsetting) |
| `Second(d)` | the second, 0-59 | [09](09-builtins.md#building-and-taking-apart-dates) |
| `Seek(n)` | the current position in file `n` (from 1) | [10](10-files.md#binary-files-get-and-put) |
| `Sgn(x)` | -1, 0 or 1 | [09](09-builtins.md#arithmetic-functions) |
| `Shell(command)` | runs a Shell command, waits, returns its return code | [10](10-files.md#shell) |
| `Shl(x, n)` | `x` shifted left `n` bits | [09](09-builtins.md#bit-shifts-and-fixed-point-arithmetic) |
| `ShrA(x, n)` | `x` shifted right `n` bits, keeping the sign | [09](09-builtins.md#bit-shifts-and-fixed-point-arithmetic) |
| `ShrL(x, n)` | `x` shifted right `n` bits, filling with zeros | [09](09-builtins.md#bit-shifts-and-fixed-point-arithmetic) |
| `Sin(a)` | the sine of an angle in radians | [09](09-builtins.md#arithmetic-functions) |
| `Sleep ms` | statement: waits `ms` milliseconds | [09](09-builtins.md#the-system-and-the-program) |
| `Space$(n)` | `n` spaces | [09](09-builtins.md#changing-case-trimming-building) |
| `Spc(n)` | in `Print`: `n` spaces | [10](10-files.md#print) |
| `Split(s [, delimiter [, limit [, compare]]])` | a String array of the pieces of `s` | [09](09-builtins.md#splitting-and-joining) |
| `Sqr(x)` | the square root | [09](09-builtins.md#arithmetic-functions) |
| `Str$(x)` | `x` as text, with a leading space if positive | [09](09-builtins.md#numbers-to-strings-and-back) |
| `StrComp(a, b [, compare])` | -1, 0 or 1: how `a` sorts against `b` | [09](09-builtins.md#searching) |
| `String$(n, char)` | `n` copies of a character | [09](09-builtins.md#changing-case-trimming-building) |
| `StrPtr(s)` | the address of a string's characters | [17](17-amigaos.md) |
| `StrReverse(s)` | `s` backwards | [09](09-builtins.md#changing-case-trimming-building) |
| `Tab[(n)]` | in `Print`: moves to column `n` (or the next zone) | [10](10-files.md#print) |
| `TagList(tag, value, ...)` | builds an AmigaOS tag list in memory and returns its address | [17](17-amigaos.md) |
| `Tan(a)` | the tangent of an angle in radians | [09](09-builtins.md#arithmetic-functions) |
| `Time` | the current time of day | [09](09-builtins.md#the-current-date-and-time) |
| `Timer` | seconds since midnight | [09](09-builtins.md#the-current-date-and-time) |
| `TimerMs` | milliseconds from a fixed start: for measuring time | [09](09-builtins.md#the-current-date-and-time) |
| `TimeSerial(h, m, s)` | the time for an hour, minute and second | [09](09-builtins.md#building-and-taking-apart-dates) |
| `TimeValue(x)` | the time part of a Date or time string | [09](09-builtins.md#building-and-taking-apart-dates) |
| `Trim$(s)` | `s` without spaces at either end | [09](09-builtins.md#changing-case-trimming-building) |
| `TypeName(x)` | the name of the type of `x` | [09](09-builtins.md#inspecting-values), [11](11-classes.md) |
| `UBound(array [, dimension])` | the highest index of an array | [04](04-data.md), [09](09-builtins.md#inspecting-values) |
| `UCase$(s)` | `s` in capitals | [09](09-builtins.md#changing-case-trimming-building) |
| `Unload form` | statement: unloads a form | [12](12-forms.md) |
| `Val(s)` | the number at the start of `s` (0 if none) | [09](09-builtins.md#numbers-to-strings-and-back) |
| `VarPtr(variable)` | the address of a variable's storage | [17](17-amigaos.md) |
| `VarType(x)` | the type of `x` as a number | [09](09-builtins.md#inspecting-values) |
| `Weekday(d [, firstday])` | the day of the week, 1-7 (1 = Sunday) | [09](09-builtins.md#building-and-taking-apart-dates) |
| `WeekdayName(n [, abbreviate])` | "Sunday"... or "Sun"... | [09](09-builtins.md#building-and-taking-apart-dates) |
| `Year(d)` | the year | [09](09-builtins.md#building-and-taking-apart-dates) |

## Not available

These functions are not built into Boing BASIC: `Filter`,
`Switch`, `QBColor`, `GetAttr`, `SetAttr`, `FileDateTime`, `FileAttr`, `GetAllSettings`,
`Date$` and `Time$` (use `Format(Date, ...)` and `Format(Time, ...)`), and statements that set
the date or time. Using one is a compile-time error: "Sub, Function or array '...' is not
defined", or for `Date$` and `Time$` "'Date$' is not a function".

See also: [Appendix A: Keywords](appendix-a-keywords.md), [Appendix C: Errors](appendix-c-errors.md).
