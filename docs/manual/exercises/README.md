# Exercises

These exercises teach Boing BASIC by building real programs, from a guessing game in the
Shell to a 3D scene with sound. Each one builds on the ones before it, so if you are new to
BASIC, do them in order. If you already know the language, start with
[Exercise 4](04-first-form.md) for windows and controls, or jump to the subject you need.

Every exercise has the same parts:

- **Goal** and **What you will learn**: what you will have made, and the parts of the language
  and runtime it uses.
- **Steps**: the program grows a little at a time. Each step is either a small complete
  program you can type in and run, or a part of the finished solution with an explanation.
- **Running it**: how to start it from a Shell (`boing run`) and from AmiForge.
- **Try this**: ideas for taking the program further on your own. There are no model answers
  for these: the chapters of the manual have what you need.

The finished programs are in the `examples/book/` drawer of the Boing BASIC sources (`Examples/Book` in the kit), one
drawer per exercise. Every sample in the exercises is checked by the manual's tests: the
console programs are run and their output compared with the text shown here.

| # | Exercise | You build | You learn |
|---|---|---|---|
| 1 | [Console programs](01-console.md) | a guessing game, a times-table quiz and a word counter, joined by a menu | `Print`, `Input`, variables, `If`, `Select Case`, loops, `Rnd`, functions, strings, projects with modules |
| 2 | [A text adventure](02-adventure.md) | "The Lost Lamp", a five-room adventure | user-defined types, arrays, the `Collection`, `On Error`, a command parser with `Split` |
| 3 | [Classes and events](03-classes.md) | a small bank of account objects | class modules, properties, `Class_Initialize`, events with `RaiseEvent` and `WithEvents`, `For Each` |
| 4 | [Your first form](04-first-form.md) | a temperature converter in a window | `.afg` layouts, controls, event Subs, the AmiForge designer |
| 5 | [A notes application](05-notes-app.md) | a text editor with menus, toolbar and status bar | menus and shortcuts, file requesters, `MsgBox`, a second window, saved settings |
| 6 | [A Canvas game](06-canvas-game.md) | "Boing Squash", a bat-and-ball game | the Canvas, a Timer game loop, the keyboard, game states, frame timing |
| 7 | [A 3D scene](07-3d-scene.md) | spinning models on a chequered floor | Engine3D: models, a floor grid, the camera, lighting, fog |
| 8 | [Sound](08-sound.md) | a sound board | the Audio object: modules, synthesised sound effects, samples, sliders |
| 9 | [Faster with C](09-extending.md) | a prime sieve sped up with a C function and a C extension class | Declare Lib "C", writing an extension, the cost of calls |

## What you need

- AmigaOS 4.1 with Boing BASIC installed (the `boing` command in your path, see
  [Using boing from the Shell](../02-shell.md)).
- Optionally AmiForge, the IDE (see [Using AmiForge](../03-amiforge.md)). Every exercise can
  also be done with a text editor and a Shell.
- For exercises 1 to 3 any computer that runs `boing` will do: console programs run the same
  everywhere. Exercises 4 to 8 open windows, play sound or draw on screen, so they need
  AmigaOS 4.

## How to work through an exercise

1. Make a drawer for your own version, for example `Work:Exercises/Console`.
2. Type each step in (or copy it), run it, and compare what you see with the output shown.
   Then change something and run it again: that is the quickest way to learn.
3. When a step is part of a bigger program, look at the full solution in `examples/book/`
   for the parts the text leaves out.
4. Finish with the "Try this" list.

If `boing run` reports an error, it gives the file, line and column, for example
`Main.bas:12:5: error: variable 'scroe' is not defined`. Go to that line: the message says what is
wrong. Run-time errors look like `Main.bas:20: runtime error 9: Subscript out of range`; the
[Errors](../08-errors.md) chapter explains them and how to handle them.

## See also

- [The manual's contents](../README.md)
