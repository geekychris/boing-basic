# Boing BASIC

A Visual Basic 6 style language for AmigaOS 4.1 (PowerPC): interpreted for a quick edit-run
cycle, or compiled to C and built with GCC into an optimised native executable. Forms are
designed in the [AmiForge](https://github.com/geekychris/amiforge) IDE, VB style: double-click
a control to write its event code.

Work in progress. See [docs/DESIGN.md](docs/DESIGN.md).

## Building and using it (host: macOS / Linux)

```
make                      # build/boing, build/libboing.a, build/include/
make test                 # every test through the VM and as a native build (host cc)
build/boing run prog.bas  # interpret
build/boing build prog.bas -o prog      # compile to C, then cc -O2
build/boing check prog.bbp              # errors as file:line:col: error: message
build/boing symbols file.bas            # declarations, for IDE outlines
build/boing build prog.bbp --target os4 # AmigaOS 4 executable via Docker (docs/os4.md)
```

Docs: [language reference](docs/language.md), [runtime C API](docs/runtime-api.md),
[forms and events](docs/forms-events.md), [AmigaOS 4](docs/os4.md).
