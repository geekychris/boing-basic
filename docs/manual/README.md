# Boing BASIC user manual

Boing BASIC is a structured BASIC for writing programs for AmigaOS 4.1, designed for programs
with windows, controls and events. Run a program straight away in the interpreter, or build it
into a fast native executable. This manual teaches the language, shows how to build programs
with and without the AmiForge IDE, and describes everything the language and its runtime
provide.

## Contents

**Getting started**

1. [Introduction](01-introduction.md): what Boing BASIC is, the kit, a first program
2. [Using Boing BASIC from the Shell](02-shell.md): `boing run`, `build`, `check`, projects
3. [Using Boing BASIC with AmiForge](03-amiforge.md): the form designer, events, menus, running and debugging

**The language**

4. [Program structure and data](04-data.md): lexical rules, types, variables, constants, enumerations, arrays, user-defined types
5. [Procedures and modules](05-procedures.md): Sub, Function and Property procedures, parameters, scope
6. [Control flow](06-control-flow.md): decisions and loops
7. [Expressions, operators and conversions](07-expressions.md)
8. [Errors and error handling](08-errors.md)
9. [Built-in functions](09-builtins.md): strings, maths, dates and times, formatting
10. [Files and the system](10-files.md): files and directories, the console, settings, the App object
11. [Classes and objects](11-classes.md): class modules, properties, events, interfaces, collections

**Programs with windows**

12. [Forms and controls](12-forms.md)
13. [Menus, toolbars, status bars and dialogs](13-menus-dialogs.md)

**Graphics and sound**

14. [Graphics with the Canvas, and Timers](14-graphics.md)
15. [3D with Engine3D](15-engine3d.md)
16. [Sound and music with Audio](16-audio.md)

**Beyond the language**

17. [Calling AmigaOS](17-amigaos.md): `Declare` and the system bindings
18. [The AmigaOS 4 desktop](18-desktop.md): fitting in with the system's windows, screens, Workbench and conventions
19. [Networking](19-networking.md): HTTP and HTTPS, web services, requests in the background
20. [Modern libraries](20-libraries.md): Dictionary, JSON, text encodings, hashing, UTC dates, StringBuilder, regular expressions, CSV, UUIDs, running commands, INI files, logging
21. [Extending Boing BASIC](21-extending.md): calling C, and extensions written in C or C++

**[Exercises](exercises/README.md)**: complete programs to build, step by step

**[Book examples](../../examples/book/README.md)**: every listing and exercise solution as a file you can run

**Appendices**

- [A. Keywords and statements](appendix-a-keywords.md)
- [B. Built-in functions](appendix-b-functions.md)
- [C. Error numbers](appendix-c-errors.md)

## Conventions

- `Code like this` is Boing BASIC, a Shell command or a file name.
- In syntax descriptions, `[square brackets]` mark optional parts and `|` separates
  alternatives.
- Shell examples show the AmigaOS Shell prompt `1>`.
- Every code example is tested: `tools/manual-check.py` compiles each one with `boing check`,
  and runs those that print, comparing their output with the manual (`make manual-test` in the
  Boing BASIC sources).
