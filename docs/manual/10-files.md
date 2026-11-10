# Files, the console and the system

This chapter covers how a program talks to the world outside it: the console (`Print`,
`Input`), files (opening, reading and writing text and binary files, records), the file system
(directories, `Dir`, `Kill`, `Name`, copying), AmigaOS paths, the `App` object, the command line
and environment variables, and saving settings with `SaveSetting`, `UseSetting` and `GetSetting`.

## The console

A program started from the Shell (or with `boing run`) has a **console**: the Shell window, or
the terminal on a host computer. `Print` writes to it and `Input` and `Line Input` read from it.
A form program on AmigaOS has a console too when it is started from the Shell.

### Print

`Print` writes its items and then starts a new line. The items are separated by `;` or `,`:

- `;` puts the next item straight after the previous one.
- `,` moves to the next **print zone**: the zones start every 14 columns (columns 1, 15, 29...).
- A `;` or `,` at the very end keeps the line open, so the next `Print` continues it.
- `Print` on its own prints an empty line.

Numbers are printed with a space in front (where the sign of a negative number goes) and a space
after them; a number between -1 and 1 has no 0 before the point. Strings are printed as they
are. Booleans print as `True` and `False`, dates in the form `3/9/2024 2:05:09 PM`, and `Null` as
`Null`:

*Listing 10.1* (`examples/book/ch10-files/listing-10-01.bas`)

<!-- run -->
```basic
Print "Hello"; "World"
Print 1; 2; -3; 0.5
Print "a", "b", "c"
Print "no new line... ";
Print "until now"
Print 2 > 1; " "; #3/9/2024#
```

```output
HelloWorld
 1  2 -3  .5 
a             b             c
no new line... until now
True 3/9/2024
```

To print numbers without the spaces, convert them first: `Print CStr(n)`, or use `Format`
([Built-in functions](09-builtins.md#format)).

Two functions can be used among the items of a `Print`:

- `Spc(n)` prints `n` spaces.
- `Tab(n)` moves to column `n` (the first column is 1). If the line is already past it, it goes
  to column `n` of the next line. `Tab` without a number moves to the next print zone, like `,`.

*Listing 10.2* (`examples/book/ch10-files/listing-10-02.bas`)

<!-- run -->
```basic
Dim i As Integer
Print "Name"; Tab(12); "Score"
For i = 1 To 3
    Print Choose(i, "Ada", "Grace", "Linus"); Tab(12); i * 100
Next
Print "x"; Spc(5); "y"
```

```output
Name       Score
Ada         100 
Grace       200 
Linus       300 
x     y
```

`Debug.Print` is the same as `Print`: it writes to the console. It is useful in form programs
for tracing what happens.

### Input and Line Input

`Input` reads values typed by the user into variables. With a prompt string and `;`, a question
mark and a space are added after the prompt; with `,` the prompt is shown as it is. Without a
prompt, `Input` shows `? `:

*Listing 10.3* (`examples/book/ch10-files/listing-10-03.bas`)

<!-- run stdin="Ada\n36" -->
```basic
Dim name As String, age As Integer
Input "Your name"; name
Input "Your age: ", age
Print "Hello "; name; ", next year you will be"; age + 1
```

```output
Your name? Your age: Hello Ada, next year you will be 37 
```

(The output above has no line breaks after the prompts because the user's typing, which ends
each line, is not part of the program's output.)

`Input` with several variables (`Input a, b, c`) expects the values on one line separated by
commas; it asks for another line if there are not enough. Spaces round a value are removed, and
a value in double quotes can contain commas. Typing letters for a numeric variable is error 13.

`Line Input` reads a whole line, commas and spaces included, into a String variable. It shows
the prompt as it is, without a question mark:

*Listing 10.4* (`examples/book/ch10-files/listing-10-04.bas`)

<!-- run stdin="  Hello, Amiga!  " -->
```basic
Dim s As String
Line Input "Say something: "; s
Print "["; s; "]"
```

```output
Say something: [  Hello, Amiga!  ]
```

When there is no more input (the end of a redirected file, or Ctrl-\ in the Shell), `Input`
and `Line Input` raise error 62, "Input past end of file".

`MsgBox` and `InputBox` show a requester on AmigaOS (and ask on the console on a host); see
[Menus and dialogs](13-menus-dialogs.md).

## Files

### Opening and closing

Before a program can read or write a file, it **opens** it and gives it a **file number**:

```text
Open path For mode [Access access] [lock] As [#]number [Len = length]
```

| Mode | What you can do |
|---|---|
| `Input` | read text, from the start. The file must exist (error 53 if not) |
| `Output` | write text. A new, empty file is made; an existing file of that name is **replaced** |
| `Append` | write text at the end of the file. The file is made if it does not exist |
| `Binary` | read and write bytes anywhere in the file. The file is made if it does not exist |
| `Random` | read and write numbered records of `Len` bytes (default 128) |

Without `For mode`, a file is opened for `Random`.

`Access Read`, `Access Write` or `Access Read Write` can follow the mode. It matters for
`Binary` and `Random`: with `Access Read` the file must already exist (error 53 otherwise), and
it is opened read-only, so you can read files on write-protected disks and CD-ROMs. The lock
words (`Shared`, `Lock Read`, `Lock Write`, `Lock Read Write`) are accepted and ignored.

The statements `Lock #n [, record [To record]]` and `Unlock #n [, record [To record]]` are
accepted too, and checked: the file must be open (error 52 if not) and the records must make
sense (a first record of at least 1, a last one not before it; error 5 otherwise). They lock
nothing, though: Boing BASIC treats an open file as belonging to one program at a time, so
there is nothing to lock. They are there so that programs which use them run unchanged.

The file number is 1 to 511. `FreeFile` gives the lowest number from 1 to 255 that is not in
use, so you do not have to keep track of them. Opening a number that is already open is error 55,
"File already open".

`Close #n` closes a file (the `#` is optional, and you can close several: `Close #1, #2`).
`Close` alone closes all open files, and so does `Reset`. A program's files are closed anyway when it ends, also
after an error, but closing a file as soon as you have finished with it makes sure everything is
written to the disk.

### Writing and reading text

`Print #n, items` writes to a file exactly what `Print` would show on the console: the same
`;`, `,`, `Tab` and `Spc` rules, and a new line at the end. `Line Input #n, s` reads the next
line back, and `EOF(n)` is True when there is nothing left to read:

*Listing 10.5* (`examples/book/ch10-files/listing-10-05.bas`)

<!-- run -->
```basic
Dim f As Integer, s As String, i As Integer

f = FreeFile
Open "log.txt" For Output As #f
Print #f, "first line"
Print #f, "value:"; 42
Close #f

Open "log.txt" For Append As #f
Print #f, "added later"
Close #f

Open "log.txt" For Input As #f
Do While Not EOF(f)
    Line Input #f, s
    i = i + 1
    Print i; "["; s; "]"
Loop
Close #f

Kill "log.txt"
```

```output
 1 [first line]
 2 [value: 42 ]
 3 [added later]
```

`Line Input #` accepts lines ending with a line feed (AmigaOS and Unix), a carriage return plus
line feed (Windows) or a carriage return alone, and does not include the line end in the string.
`Print #` ends lines with a line feed only.

`Width #n, columns` makes `Print #` and `Write #` start a new line before a character that
would go past that column, so no line in the file is longer than `columns` characters. The
width is 0 to 255 (error 5 otherwise); 0, the default, means no limit:

*Listing 10.6* (`examples/book/ch10-files/listing-10-06.bas`)

<!-- run -->
```basic
Dim f As Integer, s As String
f = FreeFile
Open "wrap.txt" For Output As #f
Width #f, 10
Print #f, "The quick brown fox jumps over the lazy dog"
Print #f, "ok"
Close #f

Open "wrap.txt" For Input As #f
Do While Not EOF(f)
    Line Input #f, s
    Print "["; s; "]"
Loop
Close #f
Kill "wrap.txt"
```

```output
[The quick ]
[brown fox ]
[jumps over]
[ the lazy ]
[dog]
[ok]
```

The text is cut at exactly that column, not between words.

### Data files: Write # and Input #

`Write #n, items` writes values separated by commas, in a form that `Input #` can read back:
strings in double quotes, numbers without spaces, `#TRUE#` and `#FALSE#`, `#NULL#`, and dates
as `#yyyy-mm-dd hh:mm:ss#`. Each `Write #` writes one line. `Input #n, variables` reads the
values, one variable after another, across lines:

*Listing 10.7* (`examples/book/ch10-files/listing-10-07.bas`)

<!-- run -->
```basic
Dim f As Integer, name As String, age As Integer, height As Double

f = FreeFile
Open "people.csv" For Output As #f
Write #f, "Ada Lovelace", 36, 1.65
Write #f, "Grace Hopper", 85, 1.68
Close #f

Open "people.csv" For Input As #f
Print Input(LOF(f), #f);           ' the whole file, as it is
Close #f

Open "people.csv" For Input As #f
Do Until EOF(f)
    Input #f, name, age, height
    Print name; " is"; age; "and"; height; "m tall"
Loop
Close #f

Kill "people.csv"
```

```output
"Ada Lovelace",36,1.65
"Grace Hopper",85,1.68
Ada Lovelace is 36 and 1.65 m tall
Grace Hopper is 85 and 1.68 m tall
```

`Input #` reads a value up to the next comma or line end, removes the spaces round it, and
converts it to the variable's type (error 13 if it is not a number and the variable is numeric).
Text in double quotes is taken as it is, commas included. `#TRUE#` and `#FALSE#` are read as
the Booleans True and False, `#NULL#` as Null, and a date between `#` signs as that Date, so
everything `Write #` writes comes back as it was, into a variable of the right type or into a
Variant. Into a Variant, an unquoted number becomes a Double and an empty value Empty.

*Listing 10.8* (`examples/book/ch10-files/listing-10-08.bas`)

<!-- run -->
```basic
Dim f As Integer, done As Boolean, born As Date, note As Variant, title As String

f = FreeFile
Open "record.txt" For Output As #f
Write #f, "Ada", True, #12/10/1815#, Null
Close #f

Open "record.txt" For Input As #f
Print Input(LOF(f), #f);
Close #f

Open "record.txt" For Input As #f
Input #f, title, done, born, note
Close #f
Print title; " "; done; " "; born; " "; IsNull(note)
Print TypeName(done); " "; TypeName(born); " "; TypeName(note)
Kill "record.txt"
```

```output
"Ada",#TRUE#,#1815-12-10 00:00:00#,#NULL#
Ada True 12/10/1815 True
Boolean Date Null
```

### Reading characters: Input()

`Input(n, #f)` (also `Input$`) reads exactly `n` characters from a file opened for `Input` or
`Binary`, line ends included. Error 62 if there are fewer than `n` left. `Input(LOF(f), #f)`
reads the whole file into one string, as in the example above.

### Binary files: Get and Put

A file opened `For Binary` is a row of bytes. `Put #n, [position], variable` writes a variable's
bytes at a byte position (the first byte is 1), and `Get #n, [position], variable` reads them
back. Without a position (`Put #n, , x`), they work at the current position and move it on.

What is written depends on the variable's type:

| Type | Bytes |
|---|---|
| Byte | 1 |
| Integer, Boolean | 2 |
| Long, Single | 4 |
| Double, Currency, Date | 8 |
| String | the characters, no length. `Get` reads as many characters as the String variable already holds, so set its length first: `s = Space(10)` |
| `String * n` | `n` characters |
| user-defined type | its fields one after another (a variable-length String field has a 2-byte length in front) |
| array | its elements one after another |
| Variant | a 2-byte type code, then the value |

Numbers are stored with the lowest byte first (little-endian). This is the same layout that
many PC file formats use, but the opposite of the 680x0 and PowerPC's own byte order, which
matters when you read a file format made on the Amiga: build the number from bytes, for
example `hi * 256 + lo`.

`Seek #n, position` moves the current position, and `Seek(n)` gives it (the next byte to be
read or written, from 1). `LOF(n)` is the length of the file in bytes and `Loc(n)` the number of
bytes before the current position. `EOF(n)` is True when the position is at the end.

*Listing 10.9* (`examples/book/ch10-files/listing-10-09.bas`)

<!-- run -->
```basic
Dim f As Integer, magic As Long, s As String, b As Byte

f = FreeFile
Open "data.bin" For Binary As #f
magic = &H424F4E47                  ' the letters B O N G
Put #f, , magic
Put #f, , "Boing!"
Print "length"; LOF(f); "position"; Seek(f)

Seek #f, 1
Get #f, , b
Print "first byte"; b; "("; Chr(b); ")"
s = Space(6)
Get #f, 5, s
Print "string ["; s; "]"; Loc(f); EOF(f)
Close #f

Kill "data.bin"
```

```output
length 10 position 11 
first byte 71 (G)
string [Boing!] 10 True
```

The first byte is `G` (&H47), the lowest byte of `magic`: the little-endian order described
above.

### Random-access files: records

A file opened `For Random` is a row of **records** of the same size, set by `Len =` (default 128
bytes). `Put #n, record, variable` writes a record and `Get #n, record, variable` reads one,
counting records from 1. A user-defined type with fixed-length fields makes a natural record,
and `Len(variable)` gives its size:

*Listing 10.10* (`examples/book/ch10-files/listing-10-10.bas`)

<!-- run -->
```basic
Type HiScore
    Points As Long
    Initials As String * 3
End Type

Dim f As Integer, h As HiScore, i As Integer

f = FreeFile
Open "scores.dat" For Random As #f Len = Len(h)
For i = 1 To 3
    h.Points = 5000 - i * 1000
    h.Initials = Choose(i, "ADA", "BOB", "CAT")
    Put #f, i, h
Next
Print "records:"; LOF(f) / Len(h); "of"; Len(h); "bytes"

Get #f, 2, h
Print h.Initials; h.Points
h.Points = 9999
Put #f, 2, h                      ' change one record in place
Get #f, 2, h
Print h.Initials; h.Points
Close #f

Kill "scores.dat"
```

```output
records: 3 of 7 bytes
BOB 3000 
BOB 9999 
```

In a Random file, `Seek(n)` and `Loc(n)` count records instead of bytes. A record number below 1
is error 63, "Bad record number". A variable-length String in a record is stored with a 2-byte
length in front; a record with no room for what you put in it is not checked, so make `Len` big
enough.

### Files and errors

The common errors when working with files:

| Error | When |
|---|---|
| 52 Bad file name or number | using a file number that is not open |
| 53 File not found | opening a missing file for `Input`; `Kill`, `FileLen`, `FileCopy`, `Name` of a missing file |
| 54 Bad file mode | e.g. `Print #` to a file opened for `Input`, `Line Input #` from one opened for `Output`, `Get` on a text file |
| 55 File already open | `Open` with a file number that is already open |
| 58 File already exists | `Name` to a name that is taken, `MkDir` of an existing directory |
| 62 Input past end of file | reading after the end |
| 70 Permission denied | the file or disk is protected, or in use |
| 75 Path/File access error | the file cannot be opened or made (bad path, empty name...); removing a directory that is not empty |
| 76 Path not found | a directory that does not exist |

A program that opens a file the user chose should be ready for these:

*Listing 10.11* (`examples/book/ch10-files/listing-10-11.bas`)

<!-- run -->
```basic
Function ReadFirstLine(ByVal path As String) As String
    Dim f As Integer
    On Error GoTo failed
    f = FreeFile
    Open path For Input As #f
    Line Input #f, ReadFirstLine
    Close #f
    Exit Function
failed:
    ReadFirstLine = "(cannot read " & path & ": " & Err.Description & ")"
    Close #f
End Function

Print ReadFirstLine("no-such-file.txt")
```

```output
(cannot read no-such-file.txt: File not found)
```

## Files and directories

| Statement or function | What it does |
|---|---|
| `Dir(pattern [, attributes])` | the first file whose name matches `pattern`; `""` if none |
| `Dir` | the next match of the last pattern; `""` when there are no more |
| `FileLen(path)` | the size of a file in bytes (error 53 if it does not exist) |
| `Kill path` | deletes a file; with a pattern (`*`, `?`, `#?`...), all the matching files (not directories) |
| `Name old As new` | renames or moves a file or directory (error 58 if `new` exists) |
| `FileCopy source, destination` | copies a file (the destination is replaced if it exists) |
| `MkDir path` | makes a directory |
| `RmDir path` | removes a directory, which must be empty |
| `ChDir path` | changes the current directory |
| `CurDir` | the current directory, as a full path |
| `GetAttr(path)` | the attributes of a file or directory, as a sum of `vb...` constants (error 53 if it does not exist) |
| `SetAttr path, attributes` | makes a file read-only (`vbReadOnly`) or writable again (`vbNormal`) |
| `FileDateTime(path)` | the date and time the file was last changed, as a Date |

### Listing a directory with Dir

`Dir(pattern)` starts a search and returns the first name that matches; each `Dir` without an
argument returns the next one, and `""` means there are no more. The names come without the
directory part. In the pattern, `*` stands for any characters and `?` for one character; upper
and lower case are treated as the same, as AmigaOS does. The AmigaOS forms work too: `#?` is
the same as `*`, and `#` before any other character means "that character any number of times,
or not at all", so `a#2.txt` matches `a.txt`, `a2.txt` and `a22.txt`. A name whose only
special character is `#` and that is the name of an existing file means that file, so
`Kill "track#1.mod"` deletes `track#1.mod`; with `*` or `?` in it, it is always a pattern. (The other AmigaOS pattern
features, such as `(a|b)`, `~` and `[a-z]`, are not understood.) `Kill` takes the same patterns.

Directories are left out unless the attributes include `vbDirectory` (16); then both files and
directories are returned. The special entries `.` and `..` that host file systems have are
never returned, as on AmigaOS. To tell files from directories, try `Dir(path, vbDirectory)` against `Dir(path)`: for a
plain name without wildcards, `Dir` returns the name if it exists, and a directory only with
`vbDirectory`.

*Listing 10.12* (`examples/book/ch10-files/listing-10-12.bas`)

<!-- run -->
```basic
Dim name As String, count As Integer, f As Integer

MkDir "pics"
f = FreeFile
Open "pics/boing.iff" For Output As #f: Close #f
Open "pics/notes.txt" For Output As #f: Close #f
MkDir "pics/old"

name = Dir("pics/*.IFF")
Do While name <> ""
    Print "picture: "; name
    name = Dir
Loop

name = Dir("pics/#?", vbDirectory)
Do While name <> ""
    count = count + 1
    name = Dir
Loop
Print count; "entries in pics"
Print "["; Dir("pics/old"); "] ["; Dir("pics/old", vbDirectory); "]"

Kill "pics/*.*"
RmDir "pics/old"
RmDir "pics"
```

```output
picture: boing.iff
 3 entries in pics
[] [old]
```

`Dir` keeps one search at a time: starting a new one with `Dir(pattern)` ends the previous one.
Collect the names into an array first if you need to look into sub-directories. The order of the
names is the order the file system gives them, which is not necessarily alphabetical.

The other attribute constants (`vbNormal`, `vbReadOnly`, `vbHidden`, `vbSystem`, `vbVolume`,
`vbArchive`) have no effect on `Dir`; they are for `GetAttr` and `SetAttr`.

### Working with files and directories

*Listing 10.13* (`examples/book/ch10-files/listing-10-13.bas`)

<!-- run -->
```basic
Dim f As Integer
f = FreeFile
Open "report.txt" For Output As #f
Print #f, "Monthly report"
Close #f

Print "size"; FileLen("report.txt")
FileCopy "report.txt", "backup.txt"
Name "report.txt" As "final.txt"
Print Dir("report.txt") = ""; " "; Dir("final.txt"); " "; Dir("backup.txt")

MkDir "archive"
Name "backup.txt" As "archive/backup.txt"
Print Dir("archive/*.txt")

Kill "final.txt"
Kill "archive/backup.txt"
RmDir "archive"
```

```output
size 15 
True final.txt backup.txt
backup.txt
```

`ChDir` changes the directory that relative names are relative to, for the rest of the program
(and `CurDir` returns it). When the program starts, the current directory is the one it was
started from (the Shell's current directory, or the project's directory in AmiForge).

### Attributes and dates: GetAttr, SetAttr, FileDateTime

`GetAttr(path)` tells you what kind of thing a name is and how it is protected. The result is
a sum of these values; test one with `And`, as in `(GetAttr(p) And vbDirectory) <> 0`:

| Constant | Value | Set when |
|---|---|---|
| `vbReadOnly` | 1 | the file can't be written (on AmigaOS: its W protection bit is cleared) |
| `vbHidden` | 2 | on a host only: the name starts with a dot |
| `vbDirectory` | 16 | it is a directory (a drawer) |
| `vbArchive` | 32 | on AmigaOS only: the A (archive) protection bit of a file is clear, which means the file has changed since a backup program last set the bit |

`vbSystem` (4) and `vbVolume` (8) are never set. A name that does not exist is error 53.

`SetAttr path, attributes` changes the protection. With `vbReadOnly` the file becomes
read-only (on AmigaOS the W and D bits are cleared, so it can't be written or deleted); without
it the file becomes writable again. On AmigaOS, `vbArchive` in the attributes clears the A bit
and leaving it out sets it; on a host `vbArchive` and `vbHidden` change nothing. `vbDirectory`
can't be set (error 5). `vbNormal` (0) is "no attributes": a writable file.

`FileDateTime(path)` is the date and time the file was last changed, in local time.

*Listing 10.14* (`examples/book/ch10-files/listing-10-14.bas`)

<!-- run -->
```basic
Dim f As Integer
f = FreeFile
Open "notes.txt" For Output As #f
Print #f, "Remember the milk"
Close #f
SetAttr "notes.txt", vbReadOnly
Print "read-only:"; (GetAttr("notes.txt") And vbReadOnly) <> 0
SetAttr "notes.txt", vbNormal
Print "read-only:"; (GetAttr("notes.txt") And vbReadOnly) <> 0
Print "changed in the last minute:"; Abs(DateDiff("s", FileDateTime("notes.txt"), Now)) < 60
Kill "notes.txt"

MkDir "work"
Print "directory:"; (GetAttr("work") And vbDirectory) <> 0
RmDir "work"

On Error Resume Next
f = GetAttr("no such file")
Print "missing file: error"; Err.Number
```

```output
read-only:True
read-only:False
changed in the last minute:True
directory:True
missing file: error 53 
```

## Paths on AmigaOS

On AmigaOS a full path starts with a **volume**, **device** or **assign** name and a colon, and
uses `/` between directories: `DH1:Games/Tank/level1.dat`, `Work:Docs/readme.txt`,
`RAM:temp.txt`. Some points to remember:

- Names are not case-sensitive: `ram:Temp.TXT` is the same file as `RAM:temp.txt`.
- A name without a colon is relative to the current directory. A path that starts with a colon
  (`:Prefs`) is relative to the root of the current volume.
- In AmigaOS, a `/` at the start (or `//` inside a path) means the parent directory, like `..`
  on other systems: `/data/x.txt` is a directory beside the current one. There is no `.` or
  `..`.
- Useful assigns: `RAM:` (the RAM disk), `T:` (temporary files), `ENV:` and `ENVARC:`
  (settings, see below), `SYS:` (the boot disk), `PROGDIR:` (the directory of the running
  program).
- On a host computer (macOS, Linux), paths are the host's, such as `/home/ada/data.txt`, and
  names may be case-sensitive.

### Files beside the program: App.Path

A program usually keeps its data files (pictures, levels, music) in its own directory.
`App.Path` is that directory, as a full path, so `App.Path & "/level1.dat"` finds a file beside
the program wherever it was installed and whatever the current directory is:

*Listing 10.15* (`examples/book/ch10-files/listing-10-15.bas`)

```basic
Dim f As Integer, s As String
f = FreeFile
Open App.Path & "/readme.txt" For Input As #f
Line Input #f, s
Close #f
Print s
```

When a program sits at the root of a volume, App.Path is just `DH1:`, and `DH1:/readme.txt`
would mean the volume's parent in AmigaOS terms. Boing BASIC's file functions treat `vol:/name`
as `vol:name`, so `App.Path & "/name"` works everywhere, on AmigaOS and on hosts.

Use `App.Path` rather than `PROGDIR:`: under `boing run`, the running program is Boing BASIC
itself, so `PROGDIR:` is the directory of `boing`, while `App.Path` is the directory of your
`.bas` or `.bbp` file. In a native program built with `boing build` the two are the same.

## The App object

`App` describes the running program:

| Member | What it is |
|---|---|
| `App.Path` | the program's directory (see above): of the `.bas`, `.bbp` or `.bbc` file under `boing run`, of the executable in a native program |
| `App.EXEName` | the program's name, without the directory or a `.bas` ending |
| `App.Title` | the program's title: the project's `Title=` line, else its `Name=`, else the program's name; you can change it (`App.Title = "Paint - " & doc`), and requester titles, `App.EnvPath` and remembered window positions use it |
| `App.EnvPath` | `ENVARC:` followed by the title: a directory for files of your own that should survive a reboot (on a host, a directory under the settings directory, see below) |
| `App.Major`, `App.Minor`, `App.Revision` | the numbers of the project's `Version=` line (`Version=1.4.2` gives 1, 4 and 2); 0 without one |
| `App.FromWorkbench` | True if the program was started by double-clicking its Workbench icon, or a project icon with the default tool `boing` (AmigaOS) |
| `App.ToolType(name [, default])` | a tooltype from the program's icon: `NAME=value` gives `"value"`, a bare `NAME` gives `"1"`, a missing one `default` (or `""`). On a host, always the default |
| `App.ToolTypeCount`, `App.ToolTypes(i)` | the number of tooltypes and each tooltype line (AmigaOS) |
| `App.ArgCount`, `App.Arg(i)` | the files the program was given: icons selected with it on the Workbench, or the names on the command line (AmigaOS) |
| `App.ReadArgs(template)`, `App.ArgValue(key)` | the arguments read with an AmigaDOS template such as `"FILE/A,SIZE/N,QUIET/S"` (`True` if they fit; up to 32 items), and each value as text; from Workbench, the tooltypes (AmigaOS; see [below](#command)) |
| `App.Notify title, text [, imagefile]` | a Ringhio notification (AmigaOS; [chapter 18](18-desktop.md#notifications)) |
| `App.HotKey name, keys` | a hotkey such as `"ctrl alt j"`, which calls `HotKey_Pressed(Name)`, and an entry in Exchange (AmigaOS; [chapter 18](18-desktop.md#commodities-a-hotkey-and-exchange)) |
| `App.FormatNumber(x [, decimals])` | the number with the decimal point and thousands separator of the user's Locale settings, and `decimals` digits after the point (2 if not given); on a host `.` and `,` ([chapter 18](18-desktop.md#number-and-date-formats)) |
| `App.FormatDate(d [, format])` | a date in the user's format: `"short"` (the default), `"long"`, `"time"`, `"datetime"`, or a pattern such as `"%Y-%m-%d"` (on a host `"short"` is an ISO date and patterns follow `strftime`) |
| `App.DecimalPoint`, `App.GroupSeparator` | the user's decimal point and thousands separator, as strings (on a host `.` and `,`) |

*Listing 10.16* (`examples/book/ch10-files/listing-10-16.bas`)

<!-- run -->
```basic
Print "App.Path is set: "; App.Path <> ""
Print "title = name: "; App.Title = App.EXEName
App.Title = "My program"
Print App.Title
Print "window width "; App.ToolType("WIDTH", "640")
```

```output
App.Path is set: True
title = name: True
My program
window width 640
```

(On a host there are no icons, so `App.ToolType` gives the default.) `App` also has members for Workbench and
ARexx integration and for requesters (`App.Request`, `App.ARexxPort`, `App.ShowHelp`, AppIcons,
catalogs...): see [Menus and dialogs](13-menus-dialogs.md). Notifications, hotkeys, Exchange's
Show, Hide and Remove (the Subs `App_Show`, `App_Hide` and `App_Quit`) and the other desktop
features are in [The AmigaOS 4 desktop](18-desktop.md).

A module of your own may be called `App` (for example a program `app.bas`): `App.Path`,
`App.Title` and the other members still reach the `App` object, unless your module has a
public member of the same name. The same goes for the runtime's classes: in a program
`http.bas`, `Dim h As Http` and `New Http` still mean the class (only `http.Something` means
your module). The one exception is `Collection`: a module `collection.bas` is an error.

## The command line and the environment

### Command

`Command` (or `Command$`) gives the arguments the program was started with, after the program's
name, joined by single spaces. Quotes round an argument are removed by the Shell:

```sh
boing run greet.bas Ada "and Grace"
```

*Listing 10.17* (`examples/book/ch10-files/listing-10-17.bas`)

```basic
If Command = "" Then
    Print "usage: greet <names>"
Else
    Print "Hello, "; Command
End If
```

```text
Hello, Ada and Grace
```

A native program gets its arguments the same way (`greet Ada "and Grace"`). A program started
from the Workbench has no command line: `Command` is `""`, and the icons it was given are in
`App.Arg(i)`. To split the arguments into words, use `Split(Command)`.

On AmigaOS a program can also read its arguments the way the system's commands do, with a
template: `App.ReadArgs("NAME/A,TIMES/N,LOUD/S")` returns `True` if the command line fits it,
and `App.ArgValue("TIMES")` gives a value as text (`"1"` for a switch that was given, `""` for
an argument that wasn't). Started from Workbench, the same template reads the icon's tooltypes
(`TIMES=3`). The details are in
[Arguments: templates and tooltypes](18-desktop.md#arguments-templates-and-tooltypes).

### Environ

`Environ(name)` (or `Environ$`) gives the value of an environment variable, or `""` if it is not
set. On AmigaOS these are the Shell's local variables (`Set`) and the global variables in `ENV:`
(`SetEnv`):

*Listing 10.18* (`examples/book/ch10-files/listing-10-18.bas`)

```basic
Print "Language: "; Environ("Language")
Print "Workbench: "; Environ("Workbench")
```

On a host, `Environ("HOME")` and the like work as usual, and `Environ(n)` with a number gives
the `n`th variable as `NAME=value`. On AmigaOS `Environ(n)` with a number gives `""`.

### Shell

`Shell(command)` runs a Shell command (on a host, a command of the host's shell) and waits for
it to finish. It returns the command's return code: 0 for success; on AmigaOS 5 is `WARN`, 10
`ERROR` and 20 `FAIL` (on a host, any failure is some number other than 0). The command's
output goes to the program's console:

*Listing 10.19* (`examples/book/ch10-files/listing-10-19.bas`)

```basic
Dim rc As Long
rc = Shell("List RAM: QUICK")
If rc <> 0 Then Print "List failed with"; rc
```

`Shell` can also be used as a statement: `Shell "Copy RAM:a.txt RAM:b.txt"`.

## Settings: SaveSetting and GetSetting

Programs often want to remember things between runs: a window position, the last file opened,
an option. `SaveSetting` stores a value under an application name, a section and a key, and
`GetSetting` reads it back:

| Statement or function | What it does |
|---|---|
| `SaveSetting app, section, key, value` | stores `value` (a string), to keep |
| `UseSetting app, section, key, value` | stores `value` until the next reboot only (AmigaOS: in `ENV:`, not `ENVARC:`) |
| `GetSetting(app, section, key [, default])` | the stored value, or `default` (`""` if not given) when there is none |
| `DeleteSetting app [, section [, key]]` | deletes one key, a whole section, or all of an application's settings |

*Listing 10.20* (`examples/book/ch10-files/listing-10-20.bas`)

<!-- run -->
```basic
SaveSetting "BoingDemo", "Window", "Left", "120"
SaveSetting "BoingDemo", "Window", "Top", CStr(45)
SaveSetting "BoingDemo", "Recent", "File1", "Work:Pictures/boing.iff"

Print GetSetting("BoingDemo", "Window", "Left", "0")
Print CLng(GetSetting("BoingDemo", "Window", "Top", "0")) + 10
Print GetSetting("BoingDemo", "Window", "Width", "640")
Print GetSetting("BoingDemo", "Recent", "File1")

DeleteSetting "BoingDemo", "Window"
Print GetSetting("BoingDemo", "Window", "Left", "(deleted)")
DeleteSetting "BoingDemo"
```

```output
120
 55 
640
Work:Pictures/boing.iff
(deleted)
```

Values are always strings: convert numbers with `CStr` when saving and `CLng`, `CDbl` or `Val`
when reading. The application name, section and key must not be empty (error 5).

**Where settings are stored.** Each key is a small text file holding the value, at
`app/section/key`:

- On AmigaOS, `SaveSetting` writes it both to `ENV:` (used now) and to `ENVARC:` (kept when the
  computer is switched off), the way AmigaOS's own preferences are kept. `GetSetting` looks in
  `ENV:` first and then in `ENVARC:`. So the example above makes
  `ENVARC:BoingDemo/Window/Left`, which you can look at with `Type` in the Shell or delete with
  `Delete ENVARC:BoingDemo ALL`. `UseSetting` writes only the `ENV:` file, which is lost when
  the computer restarts: it is the **Use** button of a settings window, as `SaveSetting` is
  its **Save** ([chapter 18](18-desktop.md#settings-in-env-and-envarc)). `DeleteSetting`
  deletes from both.
- On a host, the files are under the directory named by the environment variable
  `BOING_SETTINGS`, or `.boing` in your home directory if it is not set
  (`~/.boing/BoingDemo/Window/Left`). There is only one place there, so `UseSetting` and
  `SaveSetting` do the same.

*Listing 10.21* (`examples/book/ch10-files/listing-10-21.bas`)

<!-- run -->
```basic
' Use: a setting for this session; GetSetting finds it like a saved one
UseSetting "BoingDemo", "View", "Zoom", "200"
Print GetSetting("BoingDemo", "View", "Zoom", "100")
DeleteSetting "BoingDemo"
Print GetSetting("BoingDemo", "View", "Zoom", "100")
```

```output
200
100
```

`GetAllSettings(app, section)` gives all the keys of a section at once, as a two-dimensional
array: `all(i, 0)` is the name of a key and `all(i, 1)` its value, sorted by name, with `i`
from 0. When the section has no keys, the result is `Empty`, so test it with `IsEmpty` before
you use it as an array:

*Listing 10.22* (`examples/book/ch10-files/listing-10-22.bas`)

<!-- run -->
```basic
Dim all As Variant, i As Integer
SaveSetting "BoingDemo", "Window", "Width", "640"
SaveSetting "BoingDemo", "Window", "Height", "480"
SaveSetting "BoingDemo", "Window", "Left", "20"
all = GetAllSettings("BoingDemo", "Window")
For i = LBound(all, 1) To UBound(all, 1)
    Print all(i, 0); " = "; all(i, 1)
Next
DeleteSetting "BoingDemo"
Print IsEmpty(GetAllSettings("BoingDemo", "Window"))
```

```output
Height = 480
Left = 20
Width = 640
True
```

On AmigaOS the keys of both `ENV:` and `ENVARC:` are listed (each name once), with the value
`GetSetting` would give.

## Not available

`FileAttr` (the mode a file number was opened with) is not part of Boing BASIC: keep the mode
in a variable of your own if you need it later.

## Summary

- `Print` with `;`, `,`, `Tab(n)` and `Spc(n)` writes to the console; `Input` and `Line Input`
  read from it.
- `Open path For Input|Output|Append|Binary|Random As #n` opens a file; `FreeFile` gives a free
  number, `Close` closes it.
- Text files: `Print #`, `Write #`, `Line Input #`, `Input #`, `Input(n, #f)`, `EOF`.
- Binary and record files: `Get`, `Put`, `Seek`, `LOF`, `Loc`; numbers are little-endian.
- The file system: `Dir`, `FileLen`, `Kill`, `Name ... As`, `FileCopy`, `MkDir`, `RmDir`,
  `ChDir`, `CurDir`, `GetAttr`, `SetAttr`, `FileDateTime`.
- `Width #` wraps a file's lines; `Reset` closes every file; `Lock` and `Unlock` are accepted
  but lock nothing.
- `App.Path & "/file"` finds files beside the program; `Command`, `Environ` and `Shell` connect
  to the Shell; `SaveSetting`/`GetSetting` keep settings in `ENV:` and `ENVARC:`, and
  `UseSetting` in `ENV:` only; `GetAllSettings` lists a section.

See also: [Built-in functions](09-builtins.md), [Errors and error handling](08-errors.md),
[Menus and dialogs](13-menus-dialogs.md), [AmigaOS](17-amigaos.md).
