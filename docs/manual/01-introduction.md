# Introduction

This chapter says what Boing BASIC is, what you can make with it, and how the rest of the
manual is organised.

## What Boing BASIC is

Boing BASIC is a structured BASIC for writing programs for AmigaOS 4.1 on PowerPC. It is
designed for programs with a graphical user interface: you lay out a window with buttons,
text fields, lists and menus, and then write the code that runs when the user clicks, types or
chooses something. The same language also writes Shell programs, games with fast 2D and 3D
graphics, and music and sound programs.

A program can be run in two ways:

- **Interpreted.** `boing run` compiles the program to bytecode and runs it in the Boing BASIC
  virtual machine at once. There is no wait for a compiler, so this is the quick way to try
  something.
- **Native.** `boing build` translates the program into C and compiles it with GCC into an
  ordinary AmigaOS executable. It starts faster, runs several times faster, and needs nothing
  else installed to run.

Both behave the same: a program gives the same results interpreted and native. You can develop
with `boing run` and build a native program when you are ready to share it.

## What the language gives you

- **Structured code**: procedures (`Sub`, `Function`), modules, block `If`, `Select Case`,
  `For`, `Do ... Loop`, local variables, constants and enumerations, recursion.
- **Data**: integers of several sizes, floating point, fixed-point currency, strings,
  dates, Booleans, the `Variant` that holds any of them, arrays of any number of dimensions,
  user-defined record types, and collections.
- **Objects**: class modules with properties, methods and events, interfaces, and objects
  that free themselves when they are no longer used.
- **Errors you can handle**: `On Error` handlers, the `Err` object, and messages that name the
  file and line.
- **Windows and controls**: forms laid out in `.afg` files and drawn with ReAction, the
  AmigaOS 4 gadget system, so they follow the user's fonts and preferences. Buttons, text
  fields, lists, trees, grids, tabs, sliders, menus, toolbars, status bars, file and font
  requesters, message boxes, ARexx ports, drag and drop and icons.
- **Graphics and games**: the Canvas, a drawing surface with lines, shapes, text, images,
  transparency, keyboard and mouse input; Engine3D, a filled-polygon 3D engine; and Timers
  for game loops.
- **Sound**: Audio, which plays ProTracker modules and sound effects through AHI and can
  synthesise sounds and edit songs.
- **The whole operating system**: `Declare` calls any function of any AmigaOS library, and
  ready-made declarations for the system libraries come with Boing BASIC.
- **Extensions**: you can call your own C code and add new objects written in C or C++.

## The tools

| Tool | What it is |
|---|---|
| `boing` | The compiler and interpreter. One command does everything: run, build, check, and more. Chapter 2 describes it. |
| AmiForge | An integrated development environment for AmigaOS 4.1, with a form designer for Boing BASIC, an editor that knows the language, build and run buttons and a source-level debugger. Chapter 3 describes it. |
| GCC (the AmigaOS 4 SDK) | Needed only for native builds on the Amiga. |

You can use Boing BASIC with AmiForge, or with any text editor and the Shell. Everything in
this manual works both ways.

## The Boing BASIC kit

Boing BASIC comes as a drawer, `BoingBASIC`, holding:

| | |
|---|---|
| `boing` | the compiler and interpreter |
| `lib/libboing.a`, `include/` | the runtime library and its headers, for native builds |
| `bindings/` | declarations of the AmigaOS libraries (`exec.bi`, `dos.bi`, `intuition.bi`, ...) |
| `AmiForge` | the IDE, with its project templates in `Templates/` |
| `Examples/` | complete programs: games, applications and small examples, each with its sources |
| `Docs/` | this manual and the other guides as text files |

Copy the drawer anywhere, for example to `Work:BoingBASIC`. To use `boing` from any Shell,
either add the drawer to the path or make an assign:

```sh
Assign BOING: Work:BoingBASIC
Path BOING: ADD
```

Put those two lines in `S:User-Startup` to keep them after a reboot. Native builds on the
Amiga also need the AmigaOS 4 SDK installed, with its `SDK:` assign.

## A first program

Type this into a file called `hello.bas`:

*Listing 1.1* (`examples/book/ch01-introduction/listing-01-01.bas`)

<!-- run -->
```basic
Print "Hello from Boing BASIC!"
Dim i As Integer
For i = 1 To 3
    Print "Boing"; String(i, "!")
Next i
```

```output
Hello from Boing BASIC!
Boing!
Boing!!
Boing!!!
```

and run it from a Shell:

```sh
boing run hello.bas
```

To make a native program of it:

```sh
boing build hello.bas -o hello
hello
```

Chapter 2 explains these commands; exercise 1 builds on this program.

## How this manual is organised

- **Using Boing BASIC**: [the Shell](02-shell.md) and [AmiForge](03-amiforge.md).
- **The language**: [program structure and data](04-data.md), [procedures and modules](05-procedures.md),
  [control flow](06-control-flow.md), [expressions and conversions](07-expressions.md),
  [errors](08-errors.md), [built-in functions](09-builtins.md), [files](10-files.md) and
  [classes and objects](11-classes.md).
- **Programs with windows**: [forms and controls](12-forms.md) and
  [menus, toolbars and dialogs](13-menus-dialogs.md).
- **Graphics and sound**: [the Canvas and Timers](14-graphics.md), [Engine3D](15-engine3d.md)
  and [Audio](16-audio.md).
- **Beyond the language**: [calling AmigaOS](17-amigaos.md), [the AmigaOS 4 desktop](18-desktop.md),
  [networking](19-networking.md), [modern libraries](20-libraries.md) and
  [extending Boing BASIC with C and C++](21-extending.md).
- **[Exercises](exercises/README.md)**: a series of complete programs to build, from a Shell
  game to windowed applications, a Canvas game, a 3D scene and sound.
- **Appendices**: [keywords](appendix-a-keywords.md), [all built-in functions](appendix-b-functions.md)
  and [error numbers](appendix-c-errors.md).

Every code example in this manual is tested: each one is compiled, and those that print are
run and their output compared with what the manual shows.
