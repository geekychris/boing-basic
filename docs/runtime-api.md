# libboing runtime API

`libboing` is the runtime shared by the bytecode VM (`boing run`) and by native programs
(`boing build`). Its C API is in [`src/runtime/boing.h`](../src/runtime/boing.h); the
operating-system layer it needs is in [`src/runtime/platform.h`](../src/runtime/platform.h).
This document describes the conventions. The header is the authority on signatures.

API version: `BB_API_VERSION` = 1. Additions keep existing signatures; a change that breaks
callers bumps the version and is announced to bb-os4 / bb-ide.

## Types

| BASIC      | C type      | VarType code   | notes                                   |
|------------|-------------|----------------|-----------------------------------------|
| Boolean    | `bb_bool`   | `BB_BOOLEAN`   | int16, True = -1                        |
| Byte       | `bb_byte`   | `BB_BYTE`      | uint8                                   |
| Integer    | `bb_int`    | `BB_INTEGER`   | int16, overflow is error 6              |
| Long       | `bb_long`   | `BB_LONG`      | int32 (never C `long`)                  |
| Single     | `bb_single` | `BB_SINGLE`    | float                                   |
| Double     | `bb_double` | `BB_DOUBLE`    | double                                  |
| Currency   | `bb_cur`    | `BB_CURRENCY`  | int64, value × 10000                    |
| Date       | `bb_date`   | `BB_DATE`      | double, days since 1899-12-30           |
| String     | `bb_str *`  | `BB_STRING`    | refcounted, NULL = ""                   |
| Object / class | `bb_obj *` | `BB_OBJECT` | refcounted, NULL = Nothing             |
| Variant    | `bb_value`  | `BB_VARIANT`   | tagged union, 16 bytes                  |
| arrays     | `bb_array *`| `BB_ARRAY\|t`  | NULL = not yet dimensioned              |
| `Type` (UDT) | C struct  | `BB_UDT`       | described by a `bb_udt_desc`            |

`bb_value.type` holds the VarType code. `BB_ARRAY | elemtype` is a Variant holding an
array; `BB_REF | basetype` is a by-reference argument whose `u.p` points at the storage of
the referenced variable (see Storage).

### Storage

"Raw storage" of a variable of static type T is what a `ByRef` argument points to:
`bb_int*` for Integer, `bb_str**` for String, `bb_obj**` for objects, `bb_value*` for
Variant, `bb_array**` for arrays, the struct for a UDT. `bb_find_global()` and `BB_REF`
values use it. `bb_v_deref()` reads a `BB_REF` into a temporary view and `bb_v_store_ref()`
writes through one (converting to the target type).

## Ownership

Everything refcounted (strings, objects) or owned (Variants, arrays) follows one rule:

- **Function results are owned** by the caller (`bb_str *`, `bb_value`, `bb_array *`,
  `bb_obj *` return values). Release them with `bb_str_release`, `bb_v_release`,
  `bb_arr_free`, `bb_obj_release`.
- **Arguments are borrowed** (the callee retains what it keeps), except functions named
  `_set` (move an owned value into a variable) and the `owned` parameters marked in the
  header (`bb_v_str(owned)`, `bb_set_prop(..., owned)`).
- Assignment: `bb_str_set(&var, owned)` moves, `bb_str_assign(&var, borrowed)` copies; the
  same for `bb_obj_set/assign` and `bb_v_set/assign`.
- String literals are immortal (`bb_str_lit`, `ref < 0`): retain/release are no-ops.
- Arrays are values, as in VB: `a = b` copies (`bb_arr_assign`); an array is owned by one
  variable (or one Variant).

## Errors

VB's run-time errors are C long jumps through a stack of handler frames:

```c
bb_errframe f;
bb_frame_push(&f);
if (setjmp(f.jb) == 0) {
    ... code that may call bb_raise(...) ...
    bb_frame_pop(&f);
} else {
    /* bb_errtop is still &f: pop it, look at bb_err.number / bb_err.description */
    bb_frame_pop(&f);
}
```

- `bb_raise(n, NULL)` raises error n with VB's standard message (`bb_error_message`).
  Use VB's numbers: 5 invalid argument, 6 overflow, 9 subscript, 11 division by zero,
  13 type mismatch, 52/53/... files, 91 object not set, 380 invalid property value,
  424 object required, 438 no such property or method, 450 wrong number of arguments.
- `bb_err` is the Err object. Generated code and the VM handle `On Error` with these frames.
- With no frame the runtime prints `file:line: runtime error n: message` to stderr and
  exits with 20. `bb_line` / `bb_file` hold the current BASIC source location.
- Platform code that calls back into BASIC must not let a long jump cross its own frames:
  use `bb_call_proc()` / `bb_dispatch_event()`, which catch errors.

## Objects and dispatch

Every object starts with `bb_obj { cls, ref, sinks }` and is created with
`bb_obj_new(cls)` (zeroed memory of `cls->size` bytes, ref = 1). A class is a `bb_class`:

```c
struct bb_class {
    const char *name;                       /* TypeName */
    uint32_t size;                          /* instance size incl. header */
    int32_t (*find)(const bb_class *, const char *name);   /* name -> member id */
    void (*invoke)(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret);
    void (*terminate)(bb_obj *self);        /* refcount hit 0: release fields */
    int (*iterate)(bb_obj *self, bb_value *state, bb_value *out);   /* For Each, optional */
    const bb_member *members; int32_t nmembers;   /* optional table for bb_class_find_default */
    const bb_iface *ifaces; int32_t nifaces;      /* Implements */
    const void *vtbl;                       /* early-bound table (BASIC classes) */
    void *user;
};
```

- `find` maps a member name (case-insensitive) to an id; `""` asks for the default member
  (VB's `Item` / `Value` / `Text`), whose id is conventionally `BB_MEMBER_DEFAULT` (0).
  Return `BB_NOMEMBER` if absent; the runtime raises error 438.
  `bb_class_find_default` implements `find` over a static `bb_member` table.
- `invoke(self, id, kind, argc, argv, ret)`: `kind` is `BB_INV_METHOD`, `BB_INV_GET`,
  `BB_INV_LET` or `BB_INV_SET`. For Let/Set the new value is `argv[argc-1]`. A property
  read is a GET with the index arguments (`list.List(3)` → GET "List", argc 1). `*ret` is
  Empty on entry. Arguments are borrowed; any entry may be `BB_REF` (use `bb_v_deref`).
  Wrong argument counts → `bb_raise(450)`, bad values → `bb_raise(380)` or 13.
- The VM and generated C call members of `Object`/`Variant` expressions *late bound*
  through `bb_invoke(obj, name, kind, argc, argv)` (it calls `find` then `invoke`; the C
  back end caches the id per call site with `bb_member_id`). So **form controls are just
  `bb_class` implementations**: `ok.Text = "Go"` is `invoke(ok, find("Text"), BB_INV_LET,
  1, {"Go"})`, `list.AddItem "x"` is `invoke(list, find("AddItem"), BB_INV_METHOD, 1, ...)`.
  Statements `x = ctl` / `ctl = x` with no member use the default member.
- BASIC class modules compiled by either back end are `bb_class`es too (late-bound access
  works on them); early-bound calls on typed variables use `vtbl` instead.
- `bb_get_prop(o, "Text")` / `bb_set_prop(o, "Text", owned)` are shorthands for C code.

### Events

A source object has a list of sinks. `bb_event_connect(src, fire, ctx, tag)` adds one;
`bb_event_raise(src, index, name, argc, argv)` calls every sink's `fire`. BASIC's
`RaiseEvent` and `WithEvents` use this. Platform controls do not need it: they call the
code-behind directly (next section).

## Calling BASIC from C

The running program (VM or native) installs `bb_program_ops`; C code uses:

```c
void *p = bb_find_proc("main", "ok_Click");          /* module name, sub name; NULL if none */
int32_t err = bb_call_proc(p, argc, argv, &ret);     /* 0 or the unhandled error number */
int had = bb_dispatch_event("main", "ok", "Click", argc, argv);  /* ok_Click(...) if defined */
void *slot = bb_find_global("main", "ok", &type);    /* storage of module variable `ok` */
```

- Module names are the file base name (`main.bas` → `main`), case-insensitive. A form's
  code-behind module has the form's base name.
- `bb_dispatch_event` looks up `<object>_<event>` (VB naming: `ok_Click`,
  `Form_Load`, `Form_Unload(Cancel As Integer)`), calls it if present and returns 1; an
  unhandled run-time error inside is reported and ends the program, as in VB.
- ByRef parameters: pass `bb_v_ref(BB_INTEGER, &cancel)` to let the handler change a
  variable (Form_Unload's Cancel). Plain values are passed ByVal (copied).
- Missing trailing Optional arguments are filled in by the callee.

### Forms (forms_rt.c on bb_forms.h)

The platform forms layer is bb-os4's C interface `src/runtime/bb_forms.h` (os4/forms.c on
ReAction, posix/forms.c a stub). `src/runtime/forms_rt.c` puts BASIC on top of it:

- At start-up the program calls `bb_forms_register(module, form_name, afg_text, afg_path)`
  for every `Form=` of the project. The VM keeps the .afg text in its image (and in `.bbc`
  files); native builds embed it as a C string. This stores a *form object* in the module
  variable named after the window's `name=`. That variable is public, so `other.Show` works
  from any module. The form loads on first use, as in VB.
- `Startup=Form x` runs `bb_forms_main("x")`: load, show, `bb_forms_run()` until the last
  form is unloaded, then `bb_forms_cleanup()`.
- Loading (`bb_form_load`) creates a control object for every `id=` in the .afg and stores it
  in the code-behind's variable of that name (`bb_find_global`). The compiler declares those
  variables as `Object` (plus the form's own name; `Me` in the code-behind is the form).
- Control and form objects are `bb_class`es whose `find` interns any member name and whose
  `invoke` maps to `bb_ctl_get` / `bb_ctl_set` / `bb_ctl_call` (Variant <-> `bb_fval`;
  `List(i)` passes the index). An empty member name (default member) tries Text, Caption,
  Value. `Show`/`Hide` on a form object go to `bb_form_show/hide`; `Load x` / `Unload x`
  are `bb_form_load_obj` / `bb_form_unload_obj`.
- Events: the layer's callback becomes `bb_dispatch_event(module, ctl, event, argc, argv)`
  with `argv[i] = bb_v_ref(BB_LONG, &args[i])`. A handler declared `Cancel As Integer`
  receives a copy that is written back after the call, so ByRef event arguments work for
  any integer type (both back ends copy back through a `BB_REF` of another type).
  `has_event` is answered with `bb_find_proc`.

### Declare

The VM and generated C call `bb_declare_call(bb_declare *d, argc, uint32_t argv[])`
(`src/runtime/declare.c`). It resolves through bb-os4's `bb_decl_resolve` (bb_declare.h),
caches the handle in `d->cache`, raises the returned VB error (48/453) and calls
`bb_decl_call`. Arguments: numbers as 32-bit values, ByVal String as a pointer to the text,
ByRef and objects as addresses.

### Other OS services

`App.Path/EXEName/Title` and `Clipboard.GetText/SetText/Clear` are runtime functions
(`bb_app_path`, `bb_clipboard_get`...) on bb-os4's `bb_sys.h`. `bb_rt_init` calls
`bb_sys_init(argc, argv, NULL)`. `src/runtime/os4/platform.c` implements `platform.h` on
newlib, bb_sys and the forms layer's requesters.

## Generated C

`boing build` emits one C file that includes `boing.h` and links with `libboing.a`:

- Variables of static types are plain C variables of the types above; procedures are C
  functions (`ByRef` parameters are pointers, ByVal are values, UDTs always by pointer).
- Each statement sets `bb_line` (the BASIC line); `#line` directives map to the `.bas` files.
- Procedures containing `On Error` push a handler frame and keep their locals `volatile`.
- `main()` calls `bb_rt_init`, installs `bb_program_ops`, runs the startup code (module-level
  statements or `Sub Main`) and returns 0.

## Platform layer

`platform.h` lists the OS functions (console, time, file-system operations, directory scan,
environment, MsgBox/InputBox). The portable runtime uses only those and C stdio. `posix/`
implements them for macOS/Linux; `os4/` (bb-os4) for AmigaOS 4. MsgBox and InputBox are
console prompts on posix and requesters on OS4.
