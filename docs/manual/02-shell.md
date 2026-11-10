# Using Boing BASIC from the Shell

Everything Boing BASIC does is done by one command, `boing`. This chapter shows how to use it
from an AmigaOS Shell with any text editor: running and building programs, checking them for
errors, and organising larger programs as projects. (`boing` also runs on macOS and Linux,
where it builds programs for that computer or, with Docker, for AmigaOS 4.)

## Running a program

Write a program with any editor (NotePad, MultiEdit, GoldED, or AmiForge's editor) and save
it with the extension `.bas`:

*Listing 2.1* (`examples/book/ch02-shell/listing-02-01.bas`)

<!-- run stdin="Amy" -->
```basic
' greet.bas - asks for a name and says hello
Dim name As String
Input "What is your name"; name
Print "Hello, "; name; "!"
```

```output
What is your name? Hello, Amy!
```

Then run it:

```sh
1> boing run greet.bas
What is your name? Amy
Hello, Amy!
```

`boing run` compiles the program to bytecode and runs it in the interpreter straight away.
Anything after the program's name is passed to the program as its arguments, which it reads
with `Command()`:

```sh
1> boing run args.bas one two
```

*Listing 2.2* (`examples/book/ch02-shell/listing-02-02.bas`)

<!-- run -->
```basic
' args.bas
If Command() = "" Then
    Print "No arguments"
Else
    Print "Arguments: "; Command()
End If
```

```output
No arguments
```

`Command()` gives the arguments as one string. To read them the way AmigaOS commands do, with a
template such as `FILE/A,SIZE/N,QUIET/S`, use `App.ReadArgs` and `App.ArgValue` (see
[Arguments: templates and tooltypes](18-desktop.md#arguments-templates-and-tooltypes)).

Options for `boing run` go before the program's name:

| Option | What it does |
|---|---|
| `--error-file FILE` | If the program stops with a run-time error, also write the error message to FILE (an IDE reads it from there) |
| `-v`, `--verbose` | Print what the interpreter decides (for example about the JIT, below) |
| `--jit`, `--no-jit` | Turn the just-in-time compiler on or off (see below) |
| `--jit-force` | Use the JIT even where it would decline |

## Errors

If the program has a mistake that stops it compiling, `boing` prints where it is and what is
wrong, and does not run it:

```text
greet.bas:3:21: error: expected expression, found end of line
```

The three parts are the file, the line and the column. Most editors (and AmiForge) can jump to
that place. To check a program without running it, use `boing check`:

```sh
1> boing check greet.bas
```

It prints nothing and returns 0 when the program is correct, or prints the errors and returns 1
when it is not.

If something goes wrong while the program runs (a run-time error, such as an array index out of
range or a division by zero) and the program does not handle it, it stops with a message giving
the file, the line, the error number and its description:

```text
game.bas:42: runtime error 9: Subscript out of range
```

and the Shell sees the return code 20 (`FAIL`). [Errors and error handling](08-errors.md)
shows how a program can catch and handle errors itself.

## Building a native program

```sh
1> boing build greet.bas -o greet
1> greet
What is your name? Amy
Hello, Amy!
```

`boing build` translates the program into C and compiles it with the SDK's GCC into an
ordinary AmigaOS executable. The executable needs nothing else: you can copy it to another
Amiga without Boing BASIC. Without `-o` the program is named after the source file.

| Option | What it does |
|---|---|
| `-o NAME` | Name of the program to make |
| `--opt 0`, `1`, `2`, `s` | GCC's optimisation level: `2` (the default) is fastest, `0` compiles quickest, `s` makes the smallest program |
| `--debug` | Build with debugging information and no optimisation, for a source-level debugger (AmiForge uses it) |
| `--keep-c` | Keep the generated C file beside the program |
| `--target os4` | (On macOS or Linux) build an AmigaOS 4 program with the cross compiler in Docker |

The environment variable `BOING_CFLAGS` adds options to the GCC command line, and `BOING_OPT`
sets the optimisation level like `--opt`.

Native builds need the AmigaOS 4 SDK. `boing` finds GCC as `SDK:gcc/bin/gcc` (or `gcc` in the
path) and its own headers and library through the `BOING:` assign, or in the drawer the
`boing` command is in.

### Interpreted or native?

| | `boing run` (interpreter) | `boing build` (native) |
|---|---|---|
| Start-up | immediately | after a compile of a few seconds to a minute |
| Speed | good: most programs, including games, run at full speed | 2 to 10 times faster for calculation-heavy code; graphics run at about the same speed because they are drawn by the runtime in both cases |
| Needs | `boing` on the computer that runs it | nothing |
| Behaviour | the same | the same |

Use `boing run` while you write and test a program, and `boing build` to make the version you
give to other people.

### The JIT

On real PowerPC hardware the interpreter can compile the busiest loops of a program to machine
code while it runs (`--jit`). Under emulation (QEMU's sam460ex) this is slower rather than
faster, so the interpreter measures the machine and declines; `boing run -v` says what it
decided. You normally do not need to think about it: it is an optimisation, and a program
behaves the same either way.

## Other commands

| Command | What it does |
|---|---|
| `boing run PROG [args]` | compile to bytecode and run |
| `boing build PROG [-o OUT] [options]` | build a native program |
| `boing check PROG` | check for errors only |
| `boing compile PROG.bas -o PROG.bbc` | write the bytecode to a file; `boing run PROG.bbc` runs it later without compiling again |
| `boing emit-c PROG.bas [-o PROG.c]` | write the C code a native build compiles (for the curious, or to build it yourself) |
| `boing symbols FILE.bas` | list the declarations in a file (Subs, Functions, variables...) with their line numbers, for editors |
| `boing members [Canvas\|Engine3D\|Audio]` | list the methods and properties of the runtime's objects, for editors' completion |
| `boing disasm PROG.bas` | show the bytecode (for the curious) |

PROG may be a single `.bas` file or a project (`.bbp`, below). Run `boing` with no arguments
to see this list.

## Projects

A program larger than one file is a **project**: a text file with the extension `.bbp` that
lists the program's files. A project for a program with one form, a module and a class looks
like this:

```ini
# Boing BASIC project: Notes, a small text editor
Name=Notes
Startup=Form main
Form=main.afg
Module=Files.bas
Class=Document.cls
Stack=262144
```

Each line is `Key=value`. Lines starting with `#` or `'` are comments.

| Key | Meaning |
|---|---|
| `Name` | the program's name |
| `Startup` | where the program starts: `Form name` (show that form; the program ends when the last window closes) or `Sub Main` (run the `Sub Main` procedure, in any module) |
| `Module` | a module: a `.bas` file of procedures, variables, constants and types (one line per file) |
| `Form` | a form: its layout file `name.afg`; its code is the `.bas` file with the same name beside it (`name.bas`, the form's "code-behind") |
| `Class` | a class module, `.cls` (see [Classes and objects](11-classes.md)) |
| `Uses` | files of shared declarations, such as the ready-made AmigaOS bindings: `Uses=exec,dos,intuition` adds `exec.bi`, `dos.bi` and `intuition.bi` (a name without a dot gets `.bi`), each as a module of its own. They are looked for beside the project, then in `$BOING_BINDINGS`, then in Boing BASIC's `bindings` directory (see [Procedures](05-procedures.md#sharing-code-include-and-uses)) |
| `Stack` | the stack size of the native program in bytes (default 262144; complex windows need at least that) |
| `Icon` | the program's icon (`.info` file), used when it is packaged |
| `Title`, `Version` | information for packaging tools |

File names are relative to the project file. Run or build a project exactly like a single
file:

```sh
1> boing run Notes.bbp
1> boing build Notes.bbp -o Notes
```

A single `.bas` file is a project of one module whose program starts with its first
statement (or its `Sub Main`, if it has one).

### Where the program's files are: App.Path

A program often needs files that come with it: pictures, music, saved settings. Don't rely on
the current directory: a program started from Workbench or from another drawer has a different
one. `App.Path` is the drawer the program is in, both for a native program and for one
started with `boing run` (then it is the drawer of the `.bas` or `.bbp` file):

<!-- fragment -->
```basic
Open App.Path & "/highscores.txt" For Input As #1
```

On AmigaOS a path like `Work:/x` would be wrong; Boing BASIC turns `App.Path & "/x"` into the
right path even when the program is at the top of a volume (`Work:x`).

## Running programs from Workbench

A native program is an ordinary AmigaOS program: give it an icon and double-click it.

An interpreted program starts from Workbench too. Give its `.bas` or `.bbp` file a project icon
whose default tool is `boing` (for example `BOING:boing`), and double-clicking the icon runs the
program as `boing run` would. You can set the default tool in the icon's Information window, or
let a one-line program write the icon:

*Listing 2.3* (`examples/book/ch02-shell/listing-02-03.bas`)

```basic
' gives Notes.bbp a project icon that runs it in the interpreter
App.SaveIcon "Work:Projects/Notes/Notes.bbp", "BOING:boing"
```

A console window opens when the program first prints something (and `Input` reads from it); it
stays open at the end until you close it, so you can read the output. A program with windows
that doesn't print gets no console window. The program sees itself as started from Workbench:
`App.FromWorkbench` is `True`, `Command()` is empty, and its options come from tooltypes (see
[Interpreted programs from Workbench](18-desktop.md#interpreted-programs-from-workbench)).

To pass arguments, or to start the program the way the Shell would, use a small script instead,
and give the script a project icon whose default tool is `C:IconX`:

```sh
; Run-Notes: start Notes in the interpreter (default tool C:IconX)
Stack 262144
boing run Work:Projects/Notes/Notes.bbp
```

Programs with windows need a stack of at least 256 KB. The native programs `boing build`
makes ask for it themselves, and so does `boing`; the script above sets it for the Shell that
IconX opens.

## Building from macOS or Linux

`boing` also builds on macOS and Linux, from the Boing BASIC source distribution
(`make` builds `build/boing`). There, `boing run` and `boing build` make programs for that
computer: Shell programs work fully, which is handy for testing the language and the logic of
a program; windows, sound and AmigaOS calls work only on AmigaOS. To make an AmigaOS 4 program
on a Mac or PC with Docker installed:

```sh
build/boing build Notes.bbp --target os4 -o Notes
```

Copy the result to the Amiga.

## Summary

- `boing run prog.bas` runs a program at once; `boing build prog.bas -o prog` makes a native
  executable; `boing check` checks without running.
- Errors name the file, line and column.
- A `.bbp` project lists the modules, forms and classes of a larger program, and says where it
  starts.
- Use `App.Path` to find the program's own files.

Next: [using Boing BASIC with AmiForge](03-amiforge.md), or straight to the language in
[program structure and data](04-data.md).
