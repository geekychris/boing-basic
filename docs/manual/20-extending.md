# Extending Boing BASIC

Boing BASIC can call code written in C and C++. This chapter shows the three ways:

1. **AmigaOS libraries** with `Declare`, covered in [Calling AmigaOS](17-amigaos.md);
2. **your own C functions** with `Declare ... Lib "C"`: the quickest way to move a slow loop
   into C or to reuse existing C code;
3. **extensions**: new objects and functions written in C or C++ that a program uses exactly
   like the built-in ones (`CreateObject`, `Dim x As Name`, completion in AmiForge, names and
   argument counts checked when you compile).

Code in C or C++ is compiled and linked into your program. A native build does that by
itself; for the interpreter you build an interpreter that includes it, with `boing vm`.

## What you need

- A C compiler: on AmigaOS 4 the SDK's GCC (the same one native builds use); on macOS or
  Linux the system's `cc`. C++ needs the C++ compiler of the same toolchain (`g++`), which the
  SDK has.
- The Boing BASIC headers, `boing.h` and `boing_ext.h`, in the kit's `include/` drawer (found
  through `BOING:` or beside `boing`).

## Calling your own C functions: Declare Lib "C"

Write the functions in plain C. They don't need any Boing BASIC header:

*Listing 20.1* (`examples/book/ch20-extending/cfuncs/cfuncs.bbp`)

<!-- project: examples/book/ch20-extending/cfuncs/cfuncs.bbp -->
```basic
' main.bas - calls the C functions in cfuncs.c (CSource=cfuncs.c in cfuncs.bbp)
Declare Function CRC32 Lib "C" Alias "crc32_text" (ByVal text As String) As Long
Declare Function Distance3 Lib "C" Alias "distance3" (ByVal x As Double, ByVal y As Double, ByVal z As Double) As Double
Declare Function Ordinal Lib "C" Alias "ordinal" (ByVal n As Long) As String

Sub Main()
    Dim i As Long
    Print Hex(CRC32("The quick brown fox jumps over the lazy dog"))
    Print Distance3(2, 3, 6)
    For i = 1 To 4
        Print Ordinal(i); " ";
    Next
    Print Ordinal(11); " "; Ordinal(22); " "; Ordinal(113)
End Sub
```

The C side, `cfuncs.c`:

```c
#include <stdint.h>
#include <math.h>
#include <stdio.h>

int32_t crc32_text(const char *s)            /* the CRC-32 of a string */
{
    uint32_t c = 0xFFFFFFFFu;
    for (; *s; s++) {
        int k;
        c ^= (unsigned char)*s;
        for (k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1)));
    }
    return (int32_t)~c;
}

double distance3(double x, double y, double z)
{
    return sqrt(x * x + y * y + z * z);
}

const char *ordinal(int32_t n)               /* 1 -> "1st", 22 -> "22nd" */
{
    static char buf[32];                     /* fine: Boing BASIC copies the result */
    const char *suffix = "th";
    if (n % 100 < 11 || n % 100 > 13) {
        if (n % 10 == 1) suffix = "st";
        else if (n % 10 == 2) suffix = "nd";
        else if (n % 10 == 3) suffix = "rd";
    }
    snprintf(buf, sizeof buf, "%ld%s", (long)n, suffix);
    return buf;
}
```

and the project lists the C file with `CSource=`:

```ini
Name=CFuncs
Startup=Sub Main
Module=main.bas
CSource=cfuncs.c
```

It prints:

```text
414FA339
 7
1st 2nd 3rd 4th 11th 22nd 113th
```

`Alias` gives the C name when it differs from the BASIC one; without it the C function has the
Declare's name. The parameters must be `ByVal`, of these types:

| Boing BASIC | C |
|---|---|
| `Byte` | `uint8_t` |
| `Integer` | `int16_t` |
| `Long` | `int32_t` |
| `Boolean` | `int` (True is -1, False 0) |
| `Single` | `float` |
| `Double` | `double` |
| `String` | `const char *`, valid only during the call (copy it if you keep it) |

The result is one of the same types, or none for a `Declare Sub`. A returned `const char *`
is copied into a Boing BASIC string straight away.

## Building and running programs that use C

| | Command |
|---|---|
| native program | `boing build cfuncs.bbp -o cfuncs` compiles `cfuncs.c` with the program and links it |
| AmigaOS 4 program from a Mac or PC | `boing build cfuncs.bbp --target os4 -o cfuncs` |
| interpreter | `boing vm --project cfuncs.bbp -o myboing`, then `myboing run cfuncs.bbp` |

The interpreter can't load C code while it runs, so `boing vm` builds a new interpreter, a copy
of `boing` with your C code (and the project's extensions) linked in. It runs every program
`boing` runs, plus the ones that need that C code. Rebuild it when you change the C files.
`boing vm` takes these options:

| Option | What it does |
|---|---|
| `--project P.bbp` | include every `Extension=` and `CSource=` of the project |
| `--ext dir/name` | include an extension (repeatable) |
| `--csource file.c` | include a C file for `Lib "C"` functions (repeatable) |
| `--target os4` | build an AmigaOS 4 interpreter from a Mac or PC (Docker) |
| `-o name` | the interpreter to write |

Run a program that needs C code with the standard `boing` and it tells you:

```text
main.bas:8: runtime error 453: function 'CRC32' is not linked into this program (an extension or CSource missing)
```

## Extensions: new objects and functions

`Declare Lib "C"` is enough for a few functions. An **extension** goes further: it adds
classes (with methods and properties) and functions that the compiler knows about, so a
program uses them like Canvas or Audio:

*Listing 20.2* (`examples/book/ch20-extending/mathx/demo.bbp`)

<!-- project: examples/book/ch20-extending/mathx/demo.bbp -->
```basic
' demo.bas - uses the mathx extension (Extension=mathx in demo.bbp)
Sub Main()
    Dim s As Stats, v As Variant
    Print Clamp(15, 0, 10); Clamp(-2.5, 0, 10); Lerp(0, 100, 0.25)
    Set s = CreateObject("Stats")
    s.Name = "Rainfall"
    For Each v In Array(12, 7.5, 3, 20.25, 9)
        s.Add v
    Next
    Print s.Name; ":"; s.Count; "values, mean"; s.Mean; "from"; s.Min; "to"; s.Max
    s.Clear
    On Error Resume Next
    Print s.Mean
    Print "Error"; Err.Number; Err.Description
End Sub
```

```text
 10  0  25
Rainfall: 5 values, mean 10.35 from 3 to 20.25
Error 11 Stats.Mean: no numbers added yet
```

An extension is two files with the same name, here `mathx.c` and `mathx.bbx`, and one line in
the project:

```ini
Name=MathxDemo
Startup=Sub Main
Module=demo.bas
Extension=mathx
```

`Extension=dir/name` means `dir/name.c` (or `dir/name.cpp`) and `dir/name.bbx`, relative to
the project.

### The descriptor: name.bbx

The `.bbx` file tells the compiler what the extension provides:

```text
# mathx.bbx - what mathx.c registers: two functions and a class
function Clamp(ByVal x As Double, ByVal lo As Double, ByVal hi As Double) As Double
function Lerp(ByVal a As Double, ByVal b As Double, ByVal t As Double) As Double
class Stats
  method Add(ByVal x As Double)
  method Clear()
  property-ro Count As Long
  property-ro Mean As Double
  property-ro Min As Double
  property-ro Max As Double
  property Name As String
```

| Line | Meaning |
|---|---|
| `function Name(params) As Type` | a function that returns a value |
| `sub Name(params)` | a procedure without a value |
| `class Name` | a class; the indented lines after it are its members |
| `method Name(params) [As Type]` | a method, with a result if it has `As Type` |
| `property Name As Type` | a property the program can read and set |
| `property-ro Name As Type` | a read-only property |
| `# ...` | a comment |

Parameters are written as in a `Declare`, always `ByVal`. With the descriptor the compiler
checks every use: a misspelt member, a write to a read-only property or the wrong number of
arguments is an error when you compile (`boing check` shows the line and column), not when the
program runs. It also converts function arguments to the declared types, and
`boing members --project demo.bbp` lists the members for editors (AmiForge's completion uses
it).

### The C side

An extension includes `boing_ext.h` and ends with a `BB_EXTENSION` block that registers what it
provides. The block runs once, before the program starts:

```c
#include "boing_ext.h"

static bb_value clamp(int argc, bb_value *argv)
{
    double x = argv[0].u.d, lo = argv[1].u.d, hi = argv[2].u.d;
    return bb_v_double(x < lo ? lo : x > hi ? hi : x);
}

BB_EXTENSION(mathx)                 /* the name: the same as the files' */
{
    bb_register_function("Clamp", clamp);
    bb_register_function("Lerp", lerp);
    bb_register_class("Stats", &stats_class, new_stats);
}
```

**Functions** have the form `bb_value fn(int argc, bb_value *argv)`. The arguments arrive
already converted to the types in the `.bbx`, so a `Double` parameter is in `argv[i].u.d`, a
`Long` in `.u.l`, a `String` in `.u.s` (a `bb_str`; `bb_str_ptr(argv[i].u.s)` is its text). The
function returns a new value made with one of these:

| Make a value | Read a value (any type, converted) |
|---|---|
| `bb_v_long(n)`, `bb_v_int(n)`, `bb_v_byte(n)` | `bb_v_to_long(&v)`, `bb_v_to_int(&v)` |
| `bb_v_double(x)`, `bb_v_single(x)` | `bb_v_to_double(&v)`, `bb_v_to_single(&v)` |
| `bb_v_bool(b)` | `bb_v_to_bool(&v)` |
| `bb_v_str(bb_str_from_c("text"))` | `bb_v_to_str(&v)` (a new string: release it with `bb_str_release`) |
| `bb_v_empty()` | |

Errors are raised with `bb_raise(number, "message")`: the program sees them like any other
run-time error, catchable with `On Error` (above, `Stats.Mean` raises error 11 when there are no
numbers). `bb_raise` doesn't return.

**Classes** are a `bb_class` structure. An object is a `bb_obj` header followed by your own
fields:

```c
typedef struct stats {
    bb_obj hdr;                 /* must come first */
    long count;
    double sum, min, max;
    bb_str *name;               /* a reference we own */
} stats;

enum { M_ADD, M_CLEAR, P_COUNT, P_MEAN, P_MIN, P_MAX, P_NAME };
```

and the class provides three functions: `find` turns a member name into a number, `invoke` does
the work, and `terminate` frees what the object owns when the program lets go of it:

```c
static int32_t s_find(const bb_class *cls, const char *name)
{
    size_t i;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (!strcasecmp(members[i].name, name)) return members[i].id;
    return BB_NOMEMBER;
}

static void s_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    stats *s = (stats *)self;
    switch (id) {
    case M_ADD: {
        double x = bb_v_to_double(&argv[0]);
        if (s->count == 0 || x < s->min) s->min = x;
        if (s->count == 0 || x > s->max) s->max = x;
        s->sum += x;
        s->count++;
        return;
    }
    case P_MEAN:
        if (s->count == 0) bb_raise(11, "Stats.Mean: no numbers added yet");
        *ret = bb_v_double(s->sum / s->count);
        return;
    case P_NAME:
        if (kind & BB_INV_LET) {                      /* s.Name = value */
            bb_str *old = s->name;
            s->name = bb_v_to_str(&argv[argc - 1]);   /* the new value is the last argument */
            bb_str_release(old);
        } else {                                      /* reading s.Name */
            *ret = bb_v_str(bb_str_from_c(bb_str_ptr(s->name)));
        }
        return;
    /* ... the other members ... */
    }
    bb_raise(438, NULL);       /* object doesn't support this property or method */
}

static void s_terminate(bb_obj *self)
{
    bb_str_release(((stats *)self)->name);
}

static const bb_class stats_class = {
    "Stats", sizeof(stats), s_find, s_invoke, s_terminate, NULL,
    members, sizeof members / sizeof members[0], NULL, 0, NULL, NULL
};

static bb_obj *new_stats(void)
{
    return bb_obj_new(&stats_class);     /* zeroed, reference count 1 */
}
```

`kind` says what the program is doing: `BB_INV_METHOD` (a call), `BB_INV_GET` (reading a
property) or `BB_INV_LET` (setting one). Set `*ret` for anything that returns a value.
`bb_obj_new` makes a zeroed object; `bb_register_class` makes `CreateObject("Stats")` (or
`CreateObject("Boing.Stats")`), `Dim s As Stats` and `TypeName(s)` work. (`New Stats` is not
accepted for extension classes: create them with `CreateObject`.) The runtime counts the references
to an object and calls `terminate` when the last one goes, then frees its memory. The whole
file is `examples/book/ch20-extending/mathx/mathx.c` in the book examples.

### An extension in C++

C++ works the same way. Keep the C++ object behind a pointer inside the `bb_obj`, create it in
the class's create function, delete it in `terminate`, and never let a C++ exception reach
Boing BASIC. `BB_EXTENSION` has C linkage from C++ as well. Here a `WordCount` class uses
`std::map` and `std::string`:

```cpp
struct wc_obj { bb_obj hdr; Words *w; };          // Words is an ordinary C++ class

bb_obj *new_wc()
{
    bb_obj *o = bb_obj_new(&wc_class);
    reinterpret_cast<wc_obj *>(o)->w = new Words();
    return o;
}

void wc_terminate(bb_obj *self) { delete reinterpret_cast<wc_obj *>(self)->w; }

std::string arg_string(const bb_value *v)          // any BASIC value as a std::string
{
    bb_str *s = bb_v_to_str(v);
    std::string r(bb_str_ptr(s), s ? s->len : 0);
    bb_str_release(s);
    return r;
}

void wc_invoke(bb_obj *self, int32_t id, int, int argc, bb_value *argv, bb_value *ret)
{
    Words *w = reinterpret_cast<wc_obj *>(self)->w;
    try {
        switch (id) {
        case M_ADD: w->add(arg_string(&argv[0])); return;
        case M_COUNT: *ret = bb_v_long(w->count(arg_string(&argv[0]))); return;
        case M_TOP: *ret = bb_v_str(bb_str_from_c(w->top(bb_v_to_long(&argv[0])).c_str())); return;
        case P_DISTINCT: *ret = bb_v_long(w->distinct()); return;
        case P_TOTAL: *ret = bb_v_long(w->total()); return;
        }
    } catch (const std::bad_alloc &) {
        bb_raise(7, nullptr);                       // out of memory
    }
    bb_raise(438, nullptr);
}

BB_EXTENSION(textutil)
{
    bb_register_class("WordCount", &wc_class, new_wc);
    bb_register_function("WordTotal", word_total);
}
```

with the descriptor

```text
function WordTotal(ByVal text As String) As Long
class WordCount
  method Add(ByVal text As String)
  method Count(ByVal word As String) As Long
  method Top(ByVal n As Long) As String
  property-ro Distinct As Long
  property-ro Total As Long
```

and a program:

*Listing 20.3* (`examples/book/ch20-extending/textutil/demo.bbp`)

<!-- project: examples/book/ch20-extending/textutil/demo.bbp -->
```basic
' demo.bas - uses the textutil extension (Extension=textutil in demo.bbp)
Sub Main()
    Dim wc As WordCount
    Set wc = CreateObject("WordCount")
    wc.Add "The ball bounces. The ball spins, and the ball falls."
    wc.Add "A red and white ball!"
    Print wc.Total; "words,"; wc.Distinct; "different"
    Print "ball:"; wc.Count("Ball"); " the:"; wc.Count("THE"); " amiga:"; wc.Count("amiga")
    Print "Top 3: "; wc.Top(3)
    Print WordTotal("one two  three")
End Sub
```

```text
 15 words, 9 different
ball: 4  the: 3  amiga: 0
Top 3: ball:4 the:3 and:2
 3
```

The file is `examples/book/ch20-extending/textutil/textutil.cpp`. On AmigaOS 4 the SDK's C++
library needs the thread model `-athread=native`, which `boing build` and `boing vm` add for
C++ extensions.

## Rules for C and C++ code

- **Ownership.** Values you return are owned by the caller; values in `argv` belong to the
  runtime: read them, don't release them. A `bb_str` you keep in an object (like `name` above) is
  yours: release it when you replace it and in `terminate`.
- **Strings** are counted (`s->len`) and may contain any bytes; `bb_str_ptr` gives a
  zero-terminated pointer, or `""` for an empty string.
- **Errors** go through `bb_raise`. Never `exit()`, and never let a C++ exception escape.
- **AmigaOS 4**: compile with the same compiler and options as Boing BASIC (`boing build` and
  `boing vm` do). Don't use `-mcpu=440`-only instructions; the builds use `-mcpu=powerpc`.
- **Speed.** A call into an extension costs about as much as a call to a built-in function, so
  put whole loops in C, not single additions.
- **Not supported yet:** `New` for extension classes (use `CreateObject`), events raised by an
  extension object (for `WithEvents`), `ByRef` parameters, and loading an extension while the
  interpreter runs (it is always linked in).

## Which way to choose

| You want | Use |
|---|---|
| a function of an AmigaOS library | `Declare ... Lib "x.library"` ([chapter 17](17-amigaos.md)) |
| a few functions of your own in C, quickly | `Declare ... Lib "C"` and `CSource=` |
| objects with methods and properties, checked names, completion | an extension (`Extension=` and a `.bbx`) |
| to wrap a C++ library | an extension in C++ |

[Exercise 9](exercises/09-extending.md) builds an extension step by step.

## Summary

- `Declare Function F Lib "C" (ByVal ...) As T` plus `CSource=f.c` calls plain C functions.
- An extension is `name.c` or `name.cpp` plus `name.bbx`, added with `Extension=dir/name`; it
  registers functions and classes in `BB_EXTENSION(name)`.
- Native builds link C code by themselves; for the interpreter, `boing vm --project P.bbp -o
  myboing` builds one that includes it.
