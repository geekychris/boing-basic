# Sphere Siege

A shooter inside a hollow sphere: a port to Boing BASIC of the amiga3d game in amiga_mcp's
`examples/sphere_siege` (C, for AmigaOS 4).

Your ship rides the inside of the shell, always facing the centre, and fires inward: a shot
crosses the centre and carries on to the far wall, so it hits what is on the line on either
side. Enemies come out of the centre in spiralling trains, circle, swoop out at you and shoot
back; orbiters run along the shell itself. Every fourth wave is a siege wave of armoured
wardens.

@SHOTS@

## The game

- Darts spiral out and swoop at you; weavers swoop and shoot; orbiters run along the shell;
  wardens (every fourth wave) take three hits.
- Three ships, an extra one every 25 000 points.
- Scoring: dart 100, weaver 150, orbiter 200, warden 400, +10 a wave; 500 x the wave for
  clearing it. The eight best scores are kept in `sphere_siege.scores` beside the program.
- The radar shows enemies about the ship: red on its own side of the centre, where the view
  doesn't reach.
- An autopilot (B) plays on its own (it leads the nearest enemy and dodges bullets); it also
  plays behind the title.

| Keys | |
|---|---|
| Cursor keys / WASD | slide over the shell (on the title: the wave to start at) |
| Space | fire (hold), start |
| G | the shell's grid: every dot, every other dot, none |
| P | pause |
| B | autopilot on / off |
| Help / H | the rules and controls |
| F1 | timing overlay |
| Esc | back to the title, or quit from it |

Command line: `--wave N`, `--seed N`, `--grid 0|1|2`, `--attract`, `--perf`, `--log`,
`--bench N`.

## Files

| file | |
|---|---|
| `SphereSiege.bbp` | the game: a form project (startup form `sphere`) |
| `sphere.afg`, `sphere.bas` | the form and its code-behind |
| `SsCore.bas` | the rules, a line-by-line port of `ss_core.c`: the ship's rotation frame (no pole), shots through the centre, the enemies' phases, waves, the autopilot, the state hash over the whole game state in the C struct's order |
| `SsDraw.bas` | the picture (`render.c`): a camera built from the ship's frame, stars, the dotted shell (2688 dots, `PSetMany`), the line of fire, the vortex, enemies as spinning shapes, shots, bullets, bursts, the ship; HUD and radar |
| `SsSound.bas` | the sound effects (a stub until the audio library lands) |
| `Bench.bbp`, `BenchMain.bas` | the console bench |
| `tools/trace.c`, `tools/trace.sh` | the C original's games, for checking the port |

## Same game as the C

`tests/programs/sphere_siege` plays three autopilot games (waves 1, 4 and 6) and checks the
state hashes against the C original's, in the VM, with the JIT and native; the first is the
original's own vector (seed 1234, 6000 ticks: `D4927FCB`). The C hashes its whole `SSGame`
struct as 32-bit words; `SsStateHash` hashes the same fields in the same order.

## What changed from the original

- No bridge; command-line options instead. A table of eight high scores with name entry (the
  original kept only the best score in a file).
- The Canvas's 6 x 9 font; the picture at 320 x 256 shown at 2x; the shell's far dots one
  pixel and the nearer ones 2 x 2 (the original: 1, 2 and 2/3 pixels by distance).
- @SOUND@

## Performance

@PERF@
