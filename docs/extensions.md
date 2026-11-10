# Linked extensions

Classes and functions written in C or C++ that Boing BASIC programs use like the runtime's own
(`CreateObject("Counter")`, `Dim c As Counter`, `Clamp(x, 0, 10)`). They are linked into the
program: into a native build, or into an interpreter built for them with `boing vm`. There is no
loading at run time (no .so / .library).

## An extension

Two files with the same name: the C or C++ source, and a descriptor `name.bbx` that tells the
compiler what it registers.

```c
/* counter.c */
#include "boing_ext.h"
...
static bb_value clamp(int argc, bb_value *argv)     /* arguments as the .bbx declares them */
{
    long x = argv[0].u.l, lo = argv[1].u.l, hi = argv[2].u.l;
    return bb_v_long(x < lo ? lo : x > hi ? hi : x);
}

BB_EXTENSION(counter)                    /* runs once, before the program starts */
{
    bb_register_class("Counter", &counter_class, new_counter);
    bb_register_function("Clamp", clamp);
}
```

```
# counter.bbx
class Counter
  method Add(ByVal n As Long) As Long
  method Reset()
  property Value As Long
  property Count As Long ReadOnly
function Clamp(ByVal x As Long, ByVal lo As Long, ByVal hi As Long) As Long
sub Beep2(ByVal hz As Long)
```

- `boing_ext.h` (in `build/include`, installed beside `boing.h`): `bb_register_class(name, cls,
  create)` makes `CreateObject("name")` / `CreateObject("Boing.name")` and `As name` work;
  `bb_register_function(name, fn)` makes `name(...)` callable. A class is an ordinary `bb_class`
  (find/invoke/terminate, see `src/runtime/boing.h` and `examples/ext_counter/counter.c`).
- Helpers (stable API, `boing_ext.h`): arguments `bb_arg_long/double/bool/str/obj(argv, i)`,
  results `bb_ret_long/double/bool/str/strn/obj/empty(...)`, errors `bb_raise(number, "message")`,
  and `BB_CLASS(var, "Name", struct_type, members, invoke, terminate)` for a class whose instances
  are `struct { bb_obj hdr; ...your data... }` with a `bb_member` table `{name, id, BB_INV_xxx}`.
- `Set c = New Counter` and `CreateObject("Counter")` both use the registered create function;
  `Dim c As New Counter` (local, module-level or a class field) creates one on first use, and again after `Set c = Nothing`; a class with no create function raises 429.
- The `.bbx` lists each class's members (`method`, `property`, `property ... ReadOnly`) and each
  `function` / `sub` with its signature (ByVal only). The compiler checks member names, writes to
  read-only properties and argument counts (`boing check` gives `file:line:col` errors), converts
  function arguments to the declared types and the result from it, and `boing members --project
  P.bbp` lists the members (fields 4 and 5: signature and type) for AmiForge's completion.
- Events: `event Tick(ByVal i As Long, ByVal label As String)` lines in a class make it usable
  with `Dim WithEvents t As Ticker` (module level or a class field; handlers `t_Tick`). The
  class raises event *i* (its position among the class's `event` lines, from 0) with
  `bb_event_raise(&obj->hdr, i, "Tick", argc, argv)`; the arguments are ByVal values the caller
  owns (release strings after the call). A handler with another parameter count is a compile
  error, and so is WithEvents on a class without events. A runtime class (built into the
  runtime rather than linked from a `.bbx`) registers its event names instead:
  `bb_register_class_events("Socket", names)` with a NULL-terminated list in index order
  (`tests/ext/events/ticker.c`, `tests/c/ext_events.c`).
- C++: `BB_EXTENSION` has C linkage; keep C++ objects inside the `bb_obj` (see
  `examples/ext_shapes/shapes.cpp`). The C++ driver links (on AmigaOS 4 with `-athread=native`,
  which the OS4 `libstdc++` needs).
  - A String argument as a `std::string`: `bb_str *s = bb_v_to_str(&argv[i]);` (owned), then
    `std::string t(bb_str_ptr(s), bb_str_len(s)); bb_str_release(s);`.
  - Never let a C++ exception escape into the runtime: catch it in the invoke function (or the
    function), and call `bb_raise(n, msg)` after the try block, once C++ objects are destroyed (it longjmps), for example `std::bad_alloc` as error 7.
- A class that keeps a `bb_str` (or an object) in its instance owns that reference: release it
  in the class's terminate function.

## Using one

In the project file: `Extension=dir/name` (dir/name.c or .cpp, and dir/name.bbx).

- `boing build P.bbp` (host), `boing build P.bbp --target os4` (Docker cross build) and
  `boing build` on the Amiga (the SDK's GCC) compile and link the extension and call its init.
- The VM: `boing vm --project P.bbp -o myboing` builds an interpreter with the project's
  extensions and C functions (`--ext dir/name` and `--csource f.c` add more; `--target os4` cross
  builds an AmigaOS 4 one). Run the program with it: `./myboing run P.bbp`. The standard `boing`
  stops a program whose extension it lacks: `this program needs the extension 'counter', which
  is not linked into this interpreter`.

### Libraries: `link` lines

An extension that needs a C library says so in its `.bbx`:

```
link sqlite3          # -lsqlite3 for every target
link os4 foo          # only for AmigaOS 4 builds
link host bar         # only for host builds (macOS, Linux)
```

Native builds (host, `--target os4`, on the Amiga), `boing vm` and the standard-extension build
below add these libraries after libboing. `m` (and `auto` on AmigaOS 4) are always linked.
`boing links P.bbp [os4|host]` prints the flags.

### Standard extensions

`Extension=sqlite` with no directory, and no `sqlite.bbx` beside the project, is a standard
extension: `NAME/NAME.c` (or `.cpp`) and `NAME/NAME.bbx` found in `$BOING_EXT`, else in `ext/` of
the Boing BASIC installation (`BOING_HOME`, or the directory of the `boing` executable;
`PROGDIR:ext/` on AmigaOS), else, on hosts, the repo's `ext/` (`build/boing` → `ext/`). A name
found nowhere is a compile error naming those places.

A standard extension can also be linked into the stock interpreter, so `boing run` runs
programs that use it without a custom `boing vm`. That is a build-time list, empty by default
(a host build then needs no extra libraries):

```
make STD_EXTS=sqlite                      # host: build/boing with ext/sqlite and its link libraries
tools/build-os4.sh STD_EXTS=sqlite        # AmigaOS 4: build/os4/boing likewise
```

The kit build sets `STD_EXTS=sqlite`, so the kit's interpreter has SQLite; native programs get an
extension only from their own `Extension=` line. `STD_EXT_DIR` (default `ext`) is where the
build looks (tests/ext/run.sh builds one from tests/ext/std).

## C functions: Declare ... Lib "C"

```vb
Declare Function AddMul Lib "C" (ByVal a As Long, ByVal b As Long, ByVal c As Long) As Long
Declare Function Greet Lib "C" Alias "greet_c" (ByVal n As Long) As String
```

with `CSource=mathc.c` in the project. Parameters are ByVal Long (`int32_t`), Integer (`int16_t`),
Byte (`uint8_t`), Boolean (`int`, -1 = True), Single (`float`), Double (`double`) or String
(`const char *`, valid during the call); the result one of these (a returned string is copied).
Native builds declare the prototype and call the function directly; `boing vm --project` links
the C file with generated glue, and the standard interpreter raises error 453 ("function 'AddMul'
is not linked into this program") when one is called.

## How it fits together

- The registry (`src/runtime/ext.c`): Canvas, Engine3D and Audio register themselves the same way,
  so `CreateObject`, the compiler's `As Engine3D` and the VM's class checks all look classes up by
  name.
- Native: the generated `main()` calls `bb_ext_init_NAME()` for each `Extension=`; extension
  functions are called through `bb_ext_call()` (the registry), Lib "C" functions directly.
- VM: `boing vm` links `main.o`, the compiler and the VM (`libboingvm.a`) with the extensions and
  a generated glue file whose `bb_vm_ext_init()` runs the inits and registers the Lib "C" wrappers
  (`src/main/vmext_default.c` is the empty one of the standard `boing`). Programs record the
  extensions they need in the bytecode (`boing run` checks them at load).
- Tests: `tests/ext/run.sh` (make test): both samples and a CSource= project natively, through a
  `boing vm` interpreter and with the JIT; the missing-extension and 453 errors; the .bbx checks.
