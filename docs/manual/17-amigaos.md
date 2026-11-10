# Calling AmigaOS

This chapter shows how a Boing BASIC program calls the AmigaOS 4 libraries directly: exec,
dos, intuition, graphics, utility and any other library or device. It covers the `Declare`
statement, the ready-made bindings for about 100 system libraries, how arguments and results
are passed, and the pointer functions (`PeekL`, `PokeL`, `VarPtr`, `TagList` and friends) you
need to work with the system's structures and tag lists. It ends with hooks: BASIC procedures
that the system calls back.

Everything in this chapter is for AmigaOS 4. Most programs never need it: forms, the Canvas,
files and the other built-in features cover the usual work. Reach for `Declare` when you need
something the language does not offer, such as a system call, a library, or a device.

## Declare

A `Declare` statement, at the top of a module, tells Boing BASIC about one function in a
library. From then on you call it like any Sub or Function of your own:

*Listing 17.1* (`examples/book/ch17-amigaos/listing-17-01.bas`)

```basic
' sysinfo.bas - calling AmigaOS 4 libraries with Declare
Option Explicit

' exec.library, interface "main" (the default)
Declare Function FindTask Lib "exec.library" Alias "#50" (ByVal name_ As String) As Long
Declare Function AvailMem Lib "exec.library" Alias "#15" (ByVal attributes As Long) As Long
' dos.library, with Interface and Version written out; no Alias: found by name
Declare Function GetVar Lib "dos.library" Interface "main" Version 50 _
    (ByVal name_ As String, ByVal buffer As String, ByVal size As Long, ByVal flags As Long) As Long
' intuition.library, found by name
Declare Sub DisplayBeep Lib "intuition.library" (ByVal screen As Long)

Const MEMF_ANY = 0
Const MEMF_LARGEST = &H20000

Dim buf As String, n As Long

Print "This task is at &H"; Hex(FindTask(vbNullString))   ' vbNullString = NULL
Print "Free memory:   "; AvailMem(MEMF_ANY) \ 1024; "KB"
Print "Largest block: "; AvailMem(MEMF_LARGEST) \ 1024; "KB"

buf = Space(256)                ' a buffer GetVar fills
n = GetVar("Workbench", buf, 256, 0)
If n >= 0 Then Print "Workbench version: "; Left(buf, n)

DisplayBeep 0
Print "Beep!"
```

The full form is:

```text
[Public | Private] Declare Sub name Lib "library" [Alias "..."] [Interface "..."] [Version n] ([parameters])
[Public | Private] Declare Function name Lib "library" [Alias "..."] [Interface "..."] [Version n] ([parameters]) As type
```

- **`Lib "name"`**: the library, as `OpenLibrary` knows it: `"dos.library"`, or a device
  such as `"timer.device"` (the device is opened on unit 0 to reach its functions). The
  quotes are required.
- **`Alias`**: which function to call. `Alias "#n"` gives its **slot**, its position in the
  library's interface (the library's own functions start at 4; slots 0 to 3 are the
  interface's housekeeping and cannot be called). `Alias "RealName"` gives the function's
  name when you want to call it something else in BASIC. With no `Alias`, the BASIC name is
  the function's name.
- **`Interface "name"`**: the interface to use, `"main"` if you leave it out. A few libraries
  have functions in other interfaces: `application.library` has `"application"` and
  `"prefsobjects"`, exec.library has `"debug"`, expansion.library has `"pci"`.
- **`Version n`**: the lowest library version the program accepts.
- The parameters and the result type, as for a Function of your own (see below).

`Alias`, `Interface` and `Version` may come in any order. A `Declare` is Public unless you
write `Private`, so one module can hold the Declares for a whole program.

### What happens at the first call

Nothing is opened when the program starts. The first time you call a declared function, the
library is opened (with `Version` as the minimum version), its interface is obtained, and the
function is looked up. All later calls go straight to it. Every library opened this way stays
open until the program ends, and is then closed for you.

Finding a function by name uses a table of the functions of every library in the AmigaOS 4
SDK, built into Boing BASIC. For a library that is not in the SDK (a third-party library), you
must give the slot with `Alias "#n"`; you find it in the library's interface description
(its `.xml` file, counting from 0 with `Obtain`, `Release`, `Expunge` and `Clone`), or by
counting the function pointers in its `interfaces/*.h` C header.

### Errors

| Error | When |
|---|---|
| 48 | the library (or device) can't be opened: its name is misspelt, it isn't installed, it is older than `Version`, or the interface does not exist. The message is "Library could not be opened" |
| 453 | the library opened, but the function isn't there: a slot below 4 or past the end of the interface, or a name that is not in the built-in table (a misspelt function name, or a library that is not in the SDK). The message is "Library function not found" |
| 450 | more than 12 arguments |

They happen at the first call, so you can catch them with `On Error` like any run-time error
([Errors](08-errors.md)).

### Declare on other systems

Programs that use `Declare` compile everywhere: `boing check` and `boing build` work on the
host computer you cross-develop on. They only run on AmigaOS 4. On any other system there
are no Amiga libraries, so every declared function raises error 48 at its first call. A
program that should also run there can test for that:

*Listing 17.2* (`examples/book/ch17-amigaos/listing-17-02.bas`)

<!-- run -->
```basic
' Runs anywhere: uses exec.library when it is there, and says so when it is not
Option Explicit

Declare Function AvailMem Lib "exec.library" Alias "#15" (ByVal attributes As Long) As Long

Const MEMF_ANY = 0

Sub Main()
    Dim free As Long
    On Error Resume Next
    free = AvailMem(MEMF_ANY)
    Select Case Err.Number
        Case 0
            Print "Free memory:"; free \ 1024; "KB"
        Case 48
            Print "No exec.library here (error 48)"
        Case Else
            Print "Error"; Err.Number
    End Select
End Sub
```

```output
No exec.library here (error 48)
```

(On the Amiga it prints the free memory instead.) The pointer functions later in this chapter
also work only on AmigaOS 4: on a 64-bit host they raise error 5, because addresses there do
not fit in a Long.

## The ready-made bindings

You rarely need to write Declares yourself. The `bindings` directory of Boing BASIC
(`BOING:bindings/` on the Amiga) holds a file for each of about 100 system libraries:
`exec.bi`, `dos.bi`, `intuition.bi`, `graphics.bi`, `utility.bi`, `locale.bi`, `asl.bi`,
`datatypes.bi`, `icon.bi`, `layers.bi`, `timer.bi`, the ReAction classes (`window.bi`,
`layout.bi`, `button.bi`...) and many more. They are generated from the AmigaOS 4 SDK and
checked against its C headers. Each file holds:

- a `Declare` for every function that can be called with 32-bit arguments, each with its
  slot as `Alias "#n"`;
- every numeric constant (`#define`) of the library's headers, as `Public Const`:
  `MODE_OLDFILE`, `WA_Title`, `IDCMP_CLOSEWINDOW`, `MEMF_ANY` and so on, with the SDK's
  names and values.

*Listing 17.3* (`examples/book/ch17-amigaos/listing-17-03.bas`)

```basic
Declare Function AllocVec Lib "exec.library" Alias "#13" (ByVal byteSize As Long, ByVal attributes As Long) As Long
Declare Sub FreeVec Lib "exec.library" Alias "#28" (ByVal memoryBlock As Long)
Public Const MEMF_CLEAR = 65536
Print "These lines come from exec.bi"
```

To use a binding, add it to your project as a module. In the `.bbp` file:

```ini
# Boing BASIC project: a window and animation through intuition and graphics
Name=DeclareGfx
Startup=Sub Main
Module=declare_gfx.bas
Module=BOING:bindings/exec.bi
Module=BOING:bindings/intuition.bi
Module=BOING:bindings/graphics.bi
```

A path with a colon (`BOING:bindings/exec.bi`) is used as it is; other paths are relative to
the project file (`../../bindings/exec.bi`). A `.bi` file is an ordinary module, so you can
also open it in an editor to look up a function's arguments. (There is no `#Include`
statement: bindings go into the project.)

The generated names follow the SDK, with a few changes:

- Functions whose name is a BASIC keyword or clashes with a built-in, or that two common
  libraries share, get the library's name in front: `Dos_Open`, `Dos_Close`, `Dos_Read`,
  `Dos_Write`, `Dos_Lock`, `Dos_UnLock`, `Exec_AllocMem`, `Exec_FreeMem`.
- Parameter names that are BASIC words get a trailing `_` (`name_`, `object_`).
- Functions with a variable number of arguments (the `...Tags` forms, such as
  `OpenWindowTags`) are left out: call the tag-list form (`OpenWindowTagList`) with a
  `TagList(...)`, as shown below.
- Functions that take 64-bit, floating-point or structure arguments by value are left out;
  a comment in the `.bi` file marks each one.

A project with the `.bi` files compiles on the host too.

## Arguments

Every argument reaches the library as one 32-bit value. How a BASIC value becomes that value
depends on how the parameter is declared:

| Parameter | What is passed |
|---|---|
| `ByVal x As Long` (or Integer, Byte, Boolean) | the number. Pointers (to structures, windows, buffers) are Longs too |
| `ByVal s As String` | a pointer to the text, ending in a zero byte (a C string) |
| `ByVal s As String` with `vbNullString` | NULL (0) |
| `ByRef x As Long` (or `x As Long`: ByRef is the default) with a Long variable | a pointer to the variable, so the function can store a result in it |
| `ByVal x As Single` or `Double` | the value rounded to a whole number, halves to even as `CLng` does (97.6 -> 98, 98.5 -> 98): floating point can't be passed |
| an object | the object's address (not useful to the system) |

**Write `ByVal` for everything** unless you mean to pass a pointer to a variable. The
generated bindings do. A numeric `ByRef` parameter needs a variable of exactly the parameter's
type, because the function is given the variable's address. Anything else (a constant, an
expression, a variable of another type) is a compile error:

<!-- error: ByRef parameter 'result' of Declare GetValue needs a Long variable -->
```basic
Declare Function GetValue Lib "example.library" (ByRef result As Long) As Long

Dim n As Long, small As Integer
n = GetValue(n)          ' fine: a Long variable
n = GetValue(5)          ' error: a constant has no address
n = GetValue(small)      ' error: an Integer, not a Long
```

```text
getvalue.bas:5:14: error: ByRef parameter 'result' of Declare GetValue needs a Long variable (or declare it ByVal)
getvalue.bas:6:14: error: ByRef parameter 'result' of Declare GetValue needs a Long variable (or declare it ByVal)
```

If the function only reads the value, declare the parameter `ByVal`. If you want a pointer, it
is often clearer to declare the parameter `ByVal ... As Long` and pass `VarPtr(variable)`.

### Strings and buffers

A String argument is passed as a C string. When the argument is a String **variable**, the
function gets the variable's own memory, so a function that writes into a buffer writes into
your string. That is how you receive text: make the variable long enough first with
`Space(n)`, call, then cut it to the length the function returns (or to the first zero byte):

*Listing 17.4* (`examples/book/ch17-amigaos/listing-17-04.bas`)

```basic
Option Explicit

Declare Function GetVar Lib "dos.library" Alias "#165" _
    (ByVal name_ As String, ByVal buffer As String, ByVal size As Long, ByVal flags As Long) As Long

Function NoZero(ByVal s As String) As String
    Dim p As Long
    p = InStr(s, Chr$(0))
    If p > 0 Then NoZero = Left$(s, p - 1) Else NoZero = s
End Function

Sub Main()
    Dim buf As String, n As Long
    buf = Space(256)
    n = GetVar("Language", buf, Len(buf), 0)
    If n >= 0 Then Print "Language: "; NoZero(buf) Else Print "Language is not set"
End Sub
```

- Never let the function write more than `Len(buf)` bytes: there is no protection.
- A String **expression** (a literal, `"a" & b`) is passed as a temporary copy: fine for
  input, but anything the function writes into it is lost.
- `""` passes a pointer to an empty string, not NULL. Use `vbNullString` when the function
  wants NULL (for example `FindTask(vbNullString)`, `LockPubScreen(vbNullString)`).
- Strings are Latin-1, one byte per character, as AmigaOS expects.

### Results

A Function's result is the 32-bit value the library returns, converted to the declared type.
Declare results `As Long` (pointers and most results), or `As Integer` / `As Boolean` when the
C function returns a 16-bit value or a flag. For a function that returns a pointer to text (a
C string), declare the result `As String`: Boing BASIC copies the text into a String for you,
and a NULL result gives `""`. dos.library's `FilePart` returns the file name part of a path:

*Listing 17.5* (`examples/book/ch17-amigaos/listing-17-05.bas`)

```basic
Declare Function FilePart Lib "dos.library" (ByVal path As String) As String

Print FilePart("Work:Games/Tank/tank.bbp")
```

```text
tank.bbp
```

(On AmigaOS 4; elsewhere the call is error 48.) The copy is made at once, so it stays valid
whatever the library later does with its own memory. When you need the pointer itself, declare
the result `As Long` and read the text with `PeekS` when you want it.

A Sub ignores whatever the function returns.

### AmigaOS error codes

Many dos.library functions report failure through `IoErr()`. Read it immediately after the
call that failed: anything that writes to the console (a `Print`) changes it, and so does the
first call of a declared function, which opens its library.

*Listing 17.6* (`examples/book/ch17-amigaos/listing-17-06.bas`)

```basic
Option Explicit

Declare Function Dos_Lock Lib "dos.library" Alias "#13" (ByVal name_ As String, ByVal type_ As Long) As Long
Declare Sub Dos_UnLock Lib "dos.library" Alias "#14" (ByVal lock_ As Long)
Declare Function IoErr Lib "dos.library" Alias "#21" () As Long

Const SHARED_LOCK = -2
Const ERROR_OBJECT_NOT_FOUND = 205

Sub Main()
    Dim lk As Long, e As Long
    e = IoErr()                                   ' opens dos.library
    lk = Dos_Lock("RAM:no such file", SHARED_LOCK): e = IoErr()
    If lk = 0 Then
        If e = ERROR_OBJECT_NOT_FOUND Then Print "Not found" Else Print "Error"; e
    Else
        Dos_UnLock lk
        Print "It exists"
    End If
End Sub
```

## Memory and pointers

The system works with addresses: a window is the address of a `struct Window`, a tag list is
the address of an array of `struct TagItem`. In Boing BASIC an address is a Long. These
built-in functions read and write memory, find the address of BASIC data, and give you memory
to work in.

| Function | What it does |
|---|---|
| `PeekB(addr)` | the byte at addr, 0..255 |
| `PeekW(addr)` | the 16-bit word at addr, 0..65535 |
| `PeekL(addr)` | the 32-bit long at addr (signed, like a Long) |
| `PokeB addr, value` | store a byte |
| `PokeW addr, value` | store a 16-bit word |
| `PokeL addr, value` | store a 32-bit long |
| `PeekS(addr [, maxlen])` | the C string at addr (up to its zero byte, or at most maxlen characters); `""` for address 0 |
| `VarPtr(variable)` | the address of a variable's storage (a Long variable: its 4 bytes) |
| `StrPtr(s)` | the address of a string's characters (0 for an empty string) |
| `ObjPtr(object)` | the address of an object (0 for Nothing) |
| `AllocMem(size [, clear])` | a block of memory of `size` bytes, aligned to 8 bytes, cleared to zeros if `clear` is True |
| `FreeMem addr` | free a block from `AllocMem` (error 5 for any other address) |
| `TagList(tag, value, ...)` | build a tag list (below) |
| `FreeTagList addr` | free a tag list |

The Amiga is big-endian: the most significant byte comes first. Words and longs at odd
addresses are allowed. Address 0 raises error 5 instead of crashing; any other bad address
crashes the program (or the machine), exactly as in C, so take care.

`PeekB` and `PeekW` give unsigned values. For a signed field (a `WORD` that can be negative),
correct it yourself: `v = PeekW(a): If v >= 32768 Then v = v - 65536`.

Hex constants of four digits or fewer are Integers, so `&HBEEF` is the negative Integer
-16657. Add `&` to make a Long when you mean a 16-bit or bigger unsigned value: `&HBEEF&` is
48879.

Memory from `AllocMem` and `TagList` that you don't free is freed when the program ends. It is
ordinary private memory of your program. Memory that the system or another task keeps using
after a call (a message, an IO request, a structure you hand over for good) should come from the
system's own allocator instead: `AllocVecTagList` with `TagList(AVT_Type, MEMF_SHARED)` from
`exec.bi`, freed with `FreeVec`.

### Structures

AmigaOS structures are blocks of memory with fields at fixed offsets. To read one, add the
field's offset to the structure's address and peek; to build one, allocate memory and poke
the fields. Offsets come from the SDK's C headers (AmigaOS 4 keeps the classic layout, packed
to 2-byte boundaries). Some that are often needed:

| Structure | Field | Offset | Size |
|---|---|---|---|
| `struct Screen` | Width, Height | 12, 14 | word |
| `struct Window` | RPort (its RastPort) | 50 | long |
| `struct Window` | BorderLeft, BorderTop | 54, 55 | byte |
| `struct Window` | UserPort (its IDCMP port) | 86 | long |
| `struct IntuiMessage` | Class | 20 | long |
| `struct IntuiMessage` | Code, Qualifier | 24, 26 | word |
| `struct TagItem` | ti_Tag, ti_Data | 0, 4 | long (8 bytes a tag) |
| `struct Hook` | h_Entry, h_SubEntry, h_Data | 8, 12, 16 | long (20 bytes in all) |
| `struct ClockData` | sec, min, hour, mday, month, year, wday | 0, 2, 4, 6, 8, 10, 12 | word (14 bytes in all) |

Give offsets names with `Const` so the code says what it reads:

*Listing 17.7* (`examples/book/ch17-amigaos/listing-17-07.bas`)

```basic
Option Explicit

Declare Sub Amiga2Date Lib "utility.library" Alias "#28" (ByVal date_amiga As Long, ByVal cd As Long)

' struct ClockData (utility/date.h)
Const CD_SEC = 0, CD_MIN = 2, CD_HOUR = 4, CD_MDAY = 6, CD_MONTH = 8, CD_YEAR = 10
Const CD_SIZE = 14

Sub Main()
    Dim cd As Long
    cd = AllocMem(CD_SIZE, True)
    Amiga2Date 86400& * 366 + 3600& * 13 + 60 * 5 + 9, cd     ' seconds since 1.1.1978
    Print PeekW(cd + CD_MDAY); "."; PeekW(cd + CD_MONTH); "."; PeekW(cd + CD_YEAR); _
          PeekW(cd + CD_HOUR); ":"; PeekW(cd + CD_MIN); ":"; PeekW(cd + CD_SEC)
    FreeMem cd
End Sub
```

User-defined types (`Type ... End Type`) are not laid out like C structures, so don't pass
one to a library; build the structure in memory as above.

### Buffers for binary data

For binary data, such as a file read with dos.library, use a block from `AllocMem` and
`StrPtr` for text you send:

*Listing 17.8* (`examples/book/ch17-amigaos/listing-17-08.bas`)

```basic
Option Explicit

Declare Function Dos_Open Lib "dos.library" Alias "#4" (ByVal name_ As String, ByVal accessMode As Long) As Long
Declare Function Dos_Close Lib "dos.library" Alias "#5" (ByVal file As Long) As Long
Declare Function Dos_Read Lib "dos.library" Alias "#6" (ByVal file As Long, ByVal buffer As Long, ByVal length As Long) As Long
Declare Function Dos_Write Lib "dos.library" Alias "#7" (ByVal file As Long, ByVal buffer As Long, ByVal length As Long) As Long

Const MODE_OLDFILE = 1005
Const MODE_NEWFILE = 1006

Sub Main()
    Dim fh As Long, s As String, mem As Long, n As Long
    s = "Hello, Amiga!"
    fh = Dos_Open("T:boing_test", MODE_NEWFILE)
    If fh = 0 Then Print "Can't create the file": Exit Sub
    n = Dos_Write(fh, StrPtr(s), Len(s))
    Dos_Close fh

    fh = Dos_Open("T:boing_test", MODE_OLDFILE)
    mem = AllocMem(64, True)
    n = Dos_Read(fh, mem, 64)
    Dos_Close fh
    Print n; "bytes: "; PeekS(mem, n)
    FreeMem mem
    Kill "T:boing_test"
End Sub
```

(In real programs the built-in file statements of [Files](10-files.md) are simpler. This is
the pattern for any library that fills a buffer.)

`CopyMem` from `exec.bi` copies a block of memory: `CopyMem source, dest, size`.

## Tag lists

Many AmigaOS 4 functions take a **tag list**: pairs of a tag (which setting) and a value,
ending with `TAG_DONE`. `TagList(tag1, value1, tag2, value2, ...)` builds one in memory and
returns its address; `FreeTagList` frees it.

- Numbers are stored as they are.
- A String value is copied into the tag list's own memory, and the tag holds the address of
  that copy. So any string will do, an expression such as `"Score " & n` included: the copy
  stays valid until `FreeTagList`. (A function that writes into a string tag writes into the
  copy, not into your variable.)
- An object value is stored as its address.
- An odd number of arguments is error 450.

This excerpt from `examples/declare_gfx` opens a window with `OpenWindowTagList` and reads
its RastPort and borders from `struct Window`:

*Listing 17.9* (`examples/book/ch17-amigaos/declare_gfx/declare_gfx.bbp`)

<!-- project: examples/book/ch17-amigaos/declare_gfx/declare_gfx.bbp -->
```basic
    tags = TagList(WA_Title, "Boing BASIC: Declare'd graphics", WA_Left, 60, WA_Top, 60, _
                   WA_InnerWidth, W, WA_InnerHeight, H, WA_DragBar, 1, WA_DepthGadget, 1, _
                   WA_CloseGadget, 1, WA_Activate, 0, WA_IDCMP, IDCMP_CLOSEWINDOW)
    win = OpenWindowTagList(0, tags)
    FreeTagList tags
    If win = 0 Then
        Print "FAIL: OpenWindowTagList returned 0"
        Exit Sub
    End If
    On Error GoTo closeit
    rp = PeekL(win + WIN_RPORT)
    bx = PeekB(win + WIN_BORDERLEFT)
    by = PeekB(win + WIN_BORDERTOP)
```

and this is how it checks the window's message port for a click on the close gadget:

*Listing 17.10* (`examples/book/ch17-amigaos/declare_gfx/declare_gfx.bbp`)

<!-- project: examples/book/ch17-amigaos/declare_gfx/declare_gfx.bbp -->
```basic
Private Function CloseClicked() As Boolean
    Dim port As Long, msg As Long
    port = PeekL(win + WIN_USERPORT)
    Do
        msg = GetMsg(port)
        If msg = 0 Then Exit Do
        If PeekL(msg + IM_CLASS) = IDCMP_CLOSEWINDOW Then CloseClicked = True
        ReplyMsg msg
    Loop
End Function
```

Things the program opens through `Declare` (windows, files, locks, screens) are unknown to the
Boing BASIC runtime, so it can't close them for you. Close them yourself, also when an error
or Ctrl-C (error 18) ends the program early: declare_gfx closes its window in an `On Error`
handler for exactly that reason.

## Hooks and callbacks: AddressOf

Some system functions call a function of yours: hooks (sorting, ReAction hooks, list
browsers), and callbacks. `AddressOf ProcName` gives a native function address for a Sub or
Function in a module, as a Long, to store in a `struct Hook` or pass to a library.

- The procedure takes up to 8 parameters, all `ByVal ... As Long`; the system's arguments
  arrive there. A Function's result goes back to the system (a Sub returns 0).
- Up to 32 different procedures can be used with `AddressOf` in one program. Using the same
  procedure again gives the same address.
- An error that the callback does not handle itself ends the program with the error message,
  because it must not return into the system half done. Use `On Error` inside a callback
  that can fail.

On AmigaOS 4 a hook's function is called with the hook, the object and the message:

*Listing 17.11* (`examples/book/ch17-amigaos/listing-17-11.bas`)

```basic
' A utility.library hook whose function is written in BASIC
Option Explicit

Declare Function CallHookPkt Lib "utility.library" Alias "#17" _
    (ByVal hook As Long, ByVal object_ As Long, ByVal message As Long) As Long

' struct Hook: h_MinNode (8 bytes), h_Entry at 8, h_SubEntry at 12, h_Data at 16
Const HOOK_SIZE = 20
Const H_ENTRY = 8
Const H_DATA = 16

' called by the OS with the hook, the object and the message
Function Doubler(ByVal hook As Long, ByVal obj As Long, ByVal msg As Long) As Long
    Doubler = msg * 2 + PeekL(hook + H_DATA)
End Function

Sub Main()
    Dim hook As Long
    hook = AllocMem(HOOK_SIZE, True)          ' cleared memory for the structure
    PokeL hook + H_ENTRY, AddressOf Doubler
    PokeL hook + H_DATA, 1000
    Print "hook says"; CallHookPkt(hook, 0, 21)   ' 21 * 2 + 1000
    FreeMem hook
End Sub
```

On the Amiga this prints `hook says 1042`. On other systems `AddressOf` still returns a number
(good only for comparing) and the Declare raises error 48.

Writing your own extensions in C, and calling C code from BASIC in other ways, is the subject
of [Extending Boing BASIC](20-extending.md).

## Common mistakes

| Symptom | Likely cause |
|---|---|
| error 48 at the first call | the library name is misspelt, the library isn't installed, `Version` is too high, or the program is not running on AmigaOS 4 |
| error 453 | the function name (or `Alias`) is misspelt, or the library is not in the SDK (give `Alias "#n"`) |
| a crash in the library | a wrong slot number, a missing `ByVal`, a too-short buffer, or a structure offset that is wrong |
| text comes back empty | the buffer was an expression, not a String variable, or it was never made long enough with `Space(n)` |
| a large unsigned constant is negative | a four-digit hex constant is an Integer: write `&HBEEF&` |
| `IoErr()` says 0 | something ran between the failing call and `IoErr()` |
| a window stays open after an error | things opened through `Declare` must be closed by the program, in an error handler too |

## Summary

- `Declare Sub|Function name Lib "x.library" [Alias "#n" | "Name"] [Interface "main"]
  [Version n] (...)` calls any AmigaOS 4 library function; the library opens at the first call
  and closes at the end.
- The generated `bindings/*.bi` files declare the SDK's functions and constants: add them to
  the project with `Module=`.
- Arguments are 32-bit values: write `ByVal`, use Longs for pointers, String variables
  (made with `Space(n)`) for buffers and `vbNullString` for NULL.
- `PeekB/W/L`, `PokeB/W/L`, `PeekS`, `VarPtr`, `StrPtr`, `AllocMem` and `TagList` handle
  structures, memory and tag lists; `AddressOf` makes hooks.
- It all runs on AmigaOS 4 only; elsewhere Declares raise error 48 and the pointer functions
  error 5.

See also: [Procedures](05-procedures.md), [Errors](08-errors.md),
[Extending Boing BASIC](20-extending.md), [Appendix C: error messages](appendix-c-errors.md).
