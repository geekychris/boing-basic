# Boing BASIC — design

A Visual Basic 6 style language for AmigaOS 4.1 (PowerPC) first, portable to other platforms
later. One front end, two back ends:

- **Interpret**: compile to bytecode and run it in the Boing BASIC VM (`boing run`). Fast
  edit-run cycle, used by the IDE's Run.
- **Native**: compile to C and hand it to the platform's GCC with `-O2` (`boing build`). On
  AmigaOS 4 that is the SDK's native GCC 11.5 on the Amiga, or the walkero Docker
  cross-compiler on the Mac. The output is a normal executable linked with the Boing runtime.

Both back ends share one runtime library (`libboing`): values, strings, arrays, the built-in
functions, error handling, file I/O, forms and the OS bindings. A program must behave the same
under both; the test suite runs every test program through both and compares the output.

What has been built with it so far, with screenshots: the [gallery](gallery.md).

## Decisions (agreed with the user, 2026-11-07)

- Dialect: classic **VB6**. Not VB.NET.
- Native code: **compile to C, then GCC**. No own machine-code back end.
- Repo: `~/code/claude_world/boing_basic`, private GitHub repo `geekychris/boing-basic`.
- The IDE is **AmiForge** (`~/code/claude_world/amiforge`, github.com/geekychris/amiforge).
  Its integration is done in an AmiForge branch, not in this repo.
- Forms reuse AmiForge's existing GUI designer format **`.afg`** (ReAction layouts) rather than
  VB6's absolute-position `.frm`. Layout-based windows are how OS4 programs are built, font
  sensitive, and the designer already exists.

## Layout of this repo

```
src/compiler/   lexer, parser, AST, semantic checks, bytecode emitter, C emitter (portable C99)
src/vm/         bytecode interpreter
src/runtime/    libboing: values, strings, arrays, builtins, errors, files, forms, OS glue
src/runtime/os4/    AmigaOS 4 specific parts (forms on ReAction, Declare calls, bindings)
src/runtime/posix/  host parts (macOS/Linux) so everything but forms runs and is tested on the Mac
bindings/       generated OS library bindings (from the SDK's Include/interfaces/*.xml)
tools/          generators (bindings), build scripts (Docker cross build), deploy to the guest
tests/          .bas test programs with expected output; run through VM and native
examples/       sample programs and form projects
docs/           this file, language reference, runtime reference, IDE integration
```

The compiler, VM and runtime are portable C99 (no OS calls outside `src/runtime/<platform>/`),
so the whole language is developed and tested on the Mac with `make test`, and cross-compiled
for OS4 with the walkero Docker image (`-mcrt=newlib -O2 -mcpu=powerpc`; never `-mcpu=440*`,
see amiga_mcp's CLAUDE.md for the other OS4 rules).

## Command line

```
boing run   prog.bas [args]          compile to bytecode in memory and run
boing build prog.bbp|prog.bas [-o out] [--keep-c] [--debug]   native executable via GCC
boing check prog.bbp|prog.bas        syntax/semantic check only; errors as file:line:col: msg
boing compile prog.bas -o prog.bbc   bytecode file (runnable with `boing run prog.bbc`)
boing emit-c prog.bas -o prog.c      just the C
```

Error messages are `file:line:col: error: message` (AmiForge's build log already parses that
GCC format and makes the lines clickable). Runtime errors print
`file:line: runtime error <n>: <VB message>` and exit with code 20 (RETURN_FAIL).

## Language (VB6 subset, in priority order)

Phase 1 (core):
- Case-insensitive keywords and identifiers; `'` and `Rem` comments; `_` line continuation;
  `:` statement separator; `Option Explicit`.
- Types: `Boolean, Byte, Integer` (16-bit), `Long` (32), `Single, Double, Currency, String,
  Date, Variant, Object`; type suffixes `% & ! # @ $`; `Dim/ReDim [Preserve]/Const/Static`,
  `Public/Private/Global`; fixed and dynamic arrays with `To` bounds and `Option Base`;
  user types (`Type ... End Type`); `Enum`.
- `Sub`/`Function` with `ByVal/ByRef` (default ByRef), `Optional` with defaults, `ParamArray`;
  `Exit Sub/Function/For/Do`; `Call`.
- Control flow: `If/ElseIf/Else/End If` and single-line `If`, `Select Case` (with `Is`, `To`,
  lists), `For/Next` with `Step`, `For Each`, `Do [While|Until]/Loop [While|Until]`,
  `While/Wend`, `GoTo`/labels/line numbers, `GoSub/Return`.
- Operators with VB precedence: `^ - * / \ Mod + - & = <> < > <= >= Like Is Not And Or Xor
  Eqv Imp`; VB's implicit conversions and Variant semantics (Empty, Null).
- Errors: `On Error GoTo label / Resume Next / GoTo 0`, `Resume`, `Resume Next`, `Err` object
  (Number, Description, Source, Raise, Clear), `Error` statement.
- Builtins: strings (`Len Left Right Mid Mid$= InStr InStrRev LCase UCase Trim LTrim RTrim
  Space String Replace Split Join StrComp StrReverse Chr Asc Format Val Str Hex Oct`),
  maths (`Abs Sgn Int Fix Sqr Sin Cos Tan Atn Log Exp Rnd Randomize Round`), conversion
  (`CInt CLng CSng CDbl CStr CBool CByte CDate CVar CCur`), `IsNumeric IsEmpty IsNull IsArray
  IsDate TypeName VarType LBound UBound Array`, date/time (`Now Date Time Timer DateAdd
  DateDiff Year Month Day Hour Minute Second Weekday DateSerial TimeSerial`), `Print`/`Debug.Print`
  to the console, `Input`, `MsgBox`, `InputBox`.
- Files: `Open ... For Input/Output/Append/Binary/Random As #n`, `Close`, `Print #`, `Write #`,
  `Input #`, `Line Input #`, `Get/Put`, `EOF LOF Seek FreeFile`, `Kill Name MkDir RmDir ChDir
  CurDir Dir FileLen FileCopy`.

Phase 2:
- Modules (`.bas`) and class modules (`.cls`: properties `Property Get/Let/Set`, methods,
  `Class_Initialize/Terminate`, `New`, `Set`, `Nothing`, `Is`, `Implements`), events
  (`Event`/`RaiseEvent`/`WithEvents`), `Collection` class.
- Forms (below), `With ... End With`.
- `Declare Function/Sub` for OS calls (below).

Not planned: COM/ActiveX, OLE, DDE, `.frx` binaries, MDI forms (can come later).

## Projects

A project file `Name.bbp` (text, key=value, like VB's `.vbp`):

```
# Boing BASIC project
Name=Hello
Startup=Form main            ' or: Startup=Sub Main
Module=Main.bas
Form=main.afg                ' code-behind: main.bas beside it (same base name)
Class=Counter.cls
Stack=262144
Icon=Hello.info
```

## Forms

A form is a `.afg` file (AmiForge's designer format, see AmiForge `src/ide/GuiModel.h`) plus a
code-behind module with the same base name (`main.afg` + `main.bas`).

- Each designer object with an `id` is a control object in BASIC with that name: `ok.Text =
  "Go"`, `name.Text`, `fast.Value`, `list.AddItem "x"`, `ok.Enabled = False`. The form itself
  is `Me` inside its code-behind and is reached by the window's `name` elsewhere
  (`main.Show`, `main.Hide`, `Unload main`, `main.Caption`).
- **Events are subs named `<control>_<Event>`** in the code-behind, exactly as in VB6:
  `ok_Click`, `name_Change`, `fast_Click`, `speed_Change`, `list_Click`, `list_DblClick`,
  `Form_Load`, `Form_Unload(Cancel As Integer)`, `Form_Resize`, `Form_KeyDown(Key, Shift)`.
  The event list per control kind is defined once, in `docs/forms-events.md`, and that file is
  the contract with the IDE (the designer offers exactly these events).
- Runtime: `src/runtime/os4/forms.c` builds the window from the `.afg` at run time (the
  interpreter reads the `.afg`; `boing build` embeds it in the executable) with ReAction
  classes, runs the event loop and calls the event subs. The program ends when the last form
  is unloaded (or `End`).
- Timers (`Timer` control: `Interval`, `Enabled`, `<id>_Timer`) via timer.device, since a
  form program has no main loop of its own.

## OS bindings

Two layers:

1. **`Declare`**, VB style, for any library function:
   `Declare Function DisplayBeep Lib "intuition.library" Interface "main" (ByVal scr As Long) As Long`
   (OS4 libraries are called through interfaces; `Interface` defaults to `"main"`, version via
   `Version 50`). Arguments map to 32-bit registers per the OS4 PPC ABI. Pointers are `Long`
   (`VarPtr`, `StrPtr`, `ObjPtr` give addresses; `Peek/Poke` style helpers for structures).
2. **Generated bindings** for the SDK's libraries: `tools/genbind` reads
   `refs/os4-sdk/base/Include/interfaces/*.xml` (~110 interfaces) and writes `bindings/*.bi`
   (Declare blocks and constants as `Const`) so `#Include "exec.bi"` or a project
   `Uses=dos,intuition` gives the whole API with names and argument types. Constants come from
   the SDK headers (`#define` with numeric values). Tag lists: `TagList(TAG, value, ...)`
   builds a TagItem array.

The VM calls a Declare'd function through a small table of call stubs by argument count
(interface pointer + up to 12 32-bit args); the C back end emits a direct
`IFace->Function(...)` call. Higher-level wrappers in the runtime cover the common cases
(`Shell`, `Environ`, `Command`, `App.Path`, `Beep`, `Clipboard`, `Screen`).

## Bytecode and VM

Stack VM, one module per compiled unit, constant pool, typed instructions where the type is
known statically (Integer/Long/Double arithmetic without Variant boxing) and Variant ops
otherwise. Line table (pc → file:line) for runtime errors and the debugger. Bytecode files have
a version header.

## C back end

One C file per program (or per module), readable, with `#line` directives pointing at the
`.bas` source so GCC errors and the AmiForge debugger map to BASIC lines. Statically typed
variables become C variables (`int16_t`, `int32_t`, `double`, `bb_str *`...); Variants and
strings use the runtime. `On Error` uses the runtime's handler frames (setjmp-based). The
generated program must produce the same output as the VM for every test.

## AmiForge integration (in an AmiForge branch `feat-basic`)

- A **Boing BASIC project type** and template (New Project → Boing BASIC Form App / Console
  App); `.bas .cls .bbp` open with a BASIC lexer (folding, outline of Subs/Functions,
  completion of keywords, builtins, the project's symbols, control names and their properties).
- **Build** runs `boing check` / `boing build`; **Run** runs `boing run` (interpreted) for
  speed, **Package Release** uses `boing build` (native, optimised).
- **Designer, VB style**: with a Boing BASIC project, the designer works on the form's `.afg`
  and its code-behind instead of generating C. Double-clicking a control, or choosing an event
  from an **Events** list in the property column, opens the code-behind and jumps to
  `Sub <id>_<Event>()`, creating an empty one if it is missing (Form_Load for the form).
  Renaming a control's id offers to rename its event subs. Events that have code are shown
  in bold in the list.
- Debugger: native builds have `#line` info, so the existing debugger steps BASIC lines. VM
  debugging (breakpoints/step in `boing run`) is a later phase through a small debug protocol.

## Testing

- `make test` on the Mac: every `tests/**/*.bas` runs through `boing run` and through
  `boing build` (host GCC), output compared with the `.out` file beside it; compiler error
  tests compare messages.
- OS4: cross-build `boing` and `libboing.a`, deploy to the QEMU guest (amiga_mcp's
  `scripts/deploy-os4.sh`, devbench MCP at localhost:3000 — port may be shadowed, see
  amiga_mcp memory) and run the same tests there, natively compiled with the SDK GCC on the
  guest.
