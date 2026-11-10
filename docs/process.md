# Process: run commands, read the environment

`Process` runs a shell command, waits for it, and gives you what it printed and its return
code. It also reads and sets environment variables.

```basic
Dim p As Process
Set p = CreateObject("Process")
If p.Run("Version") = 0 Then Print "This is "; p.Output
```

(`Shell` starts a command too, but without its output; use `Process` when you need the result.)

## Running a command

| Member | |
|---|---|
| `Run(command [, input])` | runs the command line and waits for it. input, if given, is what the command reads as its input. Returns the exit code. |
| `Output` | what the command wrote to its standard output (the default member) |
| `ErrorOutput` | what it wrote to its error output |
| `OutputLines()` | `Output` split into lines, as an array (CR LF or LF; no empty last line) |
| `ExitCode` | the last command's exit code |
| `CommandLine` | the last command line |

The command goes to the system's shell: on AmigaOS the user shell (so aliases, `Path`, `$var`,
redirection and several lines separated by line feeds work); on the host `/bin/sh -c`.

**Exit codes.** On AmigaOS this is the return code: 0 OK, 5 WARN, 10 ERROR, 20 FAIL (e.g.
`Search` returns 5 when it finds nothing). On the host it is the program's exit status (127: the
command wasn't found).

On AmigaOS the output is collected in files in `T:` while the command runs, then read; on the
host through pipes. Either way the whole output is kept in memory.

```basic
' the files of a drawer, one per line
p.Run "List RAM: FILES LFORMAT %N"
For Each f In p.OutputLines()
    Print f
Next

'' feed it input: Type * copies its input to its output
p.Run "Type *", "pear" & vbLf & "apple" & vbLf
```

## Environment variables

| Member | |
|---|---|
| `GetEnv(name)` | the value of a variable, "" if it isn't set (same as `Environ(name)`) |
| `SetEnv name, value` | sets a variable for this program and the commands it runs; `SetEnv name` or a value of "" removes it. On AmigaOS a local variable (the program's shell's, like `Set`), never a global one in `ENV:`. |
| `Environment()` | all variables as an array of `"NAME=value"` Strings. On AmigaOS: the local ones, then the global ones in `ENV:` (top level, not the drawers in it). |

`Environ(n)` (n from 1) gives the same list one by one, as before.

## Errors

31201: the command couldn't be started at all (no shell, or `T:` not writable on AmigaOS).
A command that starts but fails is not an error: check the exit code.

## Tests

`tests/libs/proctest.bas` (VM, JIT and native in `make test`; on the AmigaOS 4 guest with
`tools/os4guest.py bas tests/libs/proctest.bas both`): output, exit codes, line splitting,
input, error output, setting/listing/removing variables and seeing them in a command, a large
output.
