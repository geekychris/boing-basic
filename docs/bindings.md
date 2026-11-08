# OS bindings: what is proven, and how

Boing BASIC calls AmigaOS 4 libraries through `Declare` (see [os4.md](os4.md#os-bindings)).
`tools/genbind` writes `bindings/<lib>.bi` from the SDK: one `Declare` per callable library
function, with its interface slot as `Alias "#n"`, and the library's numeric `#define`s as
`Public Const`. This page says how the bindings are checked.

## 1. Static proof against the SDK headers: `tools/bindproof`

```
tools/bindproof                 # all libraries; exit 1 on any mismatch
tools/bindproof dos exec        # some
tools/bindproof --no-compile    # only write build/bindproof/*.c and compare argument counts
```

It reads the generated `.bi` files (what programs use, not genbind's internal tables) and checks
them against SDK files genbind does not read:

| check | how | count (SDK 54.25) |
|---|---|---|
| every `Declare ... Alias "#n"` names the right function | a C `_Static_assert(offsetof(struct <X>IFace, <Function>) == sizeof(struct InterfaceData) + n * sizeof(APTR))`, compiled against `include_h/interfaces/<lib>.h` by ppc-amigaos-gcc | 2088 |
| its argument count | compared with the function pointer's prototype in `interfaces/<lib>.h` (genbind reads the XML instead) | 1960 compared |
| every `Public Const` | a `_Static_assert((uint32)(NAME) == value)` with the SDK header included, so the C compiler evaluates the macro | 8424 |

The C files are `build/bindproof/<lib>.c`, compiled with `-fsyntax-only` in the walkero Docker
image. A failed assertion or argument count is a binding bug and fails the run. A library whose
SDK headers don't compile on their own is listed as a "header problem" (its checks unproven)
and fails only with `--strict`.

Found so far: camd.xml marks variadic functions with `<arg type="..."/>` instead of
`<vararg/>`; genbind made 6 fixed-argument Declares out of them (CreateMidi, SetMidiAttrs, ...).
Fixed: they are left out now, like every variadic function (use the TagList form).

Not covered by the static proof: functions whose C name differs from the XML name (about 130:
they get no argument-count comparison), and the meaning of each argument (types are all
32-bit words; see 2).

## 2. Behaviour on the guest: `tests-os4/bindings/libs.bbp`

Real calls through Boing BASIC, with the generated `.bi` files and hand-written Declares,
printing TAP lines compared with `libs.out` (nothing machine-specific is printed):

```
tools/os4guest.py bas tests-os4/bindings/libs.bbp both    # VM and native build
```

| library | calls |
|---|---|
| exec | FindTask(NULL) via the binding and via a Declare by name; AllocVecTagList with `TagList(AVT_Type, MEMF_PRIVATE, AVT_ClearWithValue, 0)`, FreeVec; PokeL/W/B + PeekL/W/B round trip (big-endian); CopyMem; PeekS; AvailMem |
| dos | Open/Write/Close/Open/Read of a T: file (StrPtr, AllocMem buffers); Lock/NameFromLock/UnLock; Lock of a missing file + IoErr = ERROR_OBJECT_NOT_FOUND; SetVar/GetVar (Space(n) buffer)/DeleteVar |
| utility | Stricmp, Strnicmp, ToUpper (Declare with `Interface` and `Version`), GetTagData and FindTagItem on a `TagList(...)`, Amiga2Date into a struct ClockData |
| intuition, graphics | LockPubScreen(NULL) and its size; OpenWindowTagList with a tag list; the window's RastPort; SetAPen + RectFill, checked with ReadPixel; CloseWindow |
| locale | OpenLocale(NULL), ConvToUpper, CloseLocale |
| error paths | a missing library (error 48), `Version 9999` (error 48), an unknown function name (error 453) |

It needs the pointer builtins `PeekB/W/L`, `PokeB/W/L`, `PeekS`, `StrPtr`, `VarPtr`,
`TagList`, `AllocMem/FreeMem` (requested from the compiler side) and `vbNullString` passed as
NULL. Until then the call glue itself is proven from C:

- `tests/os4/declare_test.c` (21/21 on the guest, cross and native SDK GCC): resolution by name
  and by `#n`, an 11-argument call (stack arguments), a device interface (timer.device),
  error 48/453 paths, version checks.
- `tests-os4/declare/declare.bbp` (native build on the guest: 7/8, the failure is
  vbNullString): bindings and Declares from BASIC, a String argument, a Space(n) buffer.

## 3. Regenerating

```
tools/genbind --slots src/runtime/os4/os4_slots.c    # bindings/*.bi + the by-name slot table
tools/bindproof                                       # then prove them
```
