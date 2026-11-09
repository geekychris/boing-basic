# Ace Pilot 2 (Boing BASIC)

A biplane war in 3D, in Boing BASIC: a port of amiga_mcp's
[`examples/ace_pilot2`](https://github.com/geekychris/amiga_games/tree/main/ace_pilot2)
(C on the amiga3d engine).

You fly a Swallow scout of Larkspur Squadron against the Grauland air service, over the
trenches and the river Sellen, from behind (the chase view) or from the cockpit, with its upper
wing overhead, its struts, the twin guns on the cowling and their ring sight.


| Key | |
|---|---|
| Left / Right | bank |
| Up / Down | nose down / nose up (I inverts) |
| Space | guns |
| A / Z | throttle up / down |
| V or C | chase view / cockpit |
| I | invert up and down |
| P | pause |
| B | autopilot on / off |
| Help / H | how to fly, the controls |
| M | effects on / off |
| F9 | timing overlay |
| Esc | title / quit |

On the title, Up / Down choose the mission to start from; Space or Return goes to its briefing.

The eight missions are the C's: **Dawn Patrol** (the patrol line, Wasps after the first
marker), **Eyes in the Sky** (two balloons and their guns), **Shepherd** (escort two Herons to
Orme and back), **Iron Road** (stop the train), **Hold the Line** (four Ox bombers), **Supply
Lines** (four dumps at Orme), **Hornets' Nest** (the aerodrome at Kessin) and **The Grey Falcon**.
Three aeroplanes: lose one and you fly the mission again; lose all three and the squadron
grounds you. Rank goes by score.


## What is the same, what changed

Kept from the C original:

- **The whole war, exactly.** `ApCore.bas` is `ap_core.c` line for line (1300 lines of C): the
  flight model (thrust, drag, gravity along the path, bank to turn, the nose dropping in a bank,
  the stall), the guns and their heat, bullets swept against aeroplanes and ground targets, the
  AA guns' fused shells, the enemy pilots (patrol, pursue with lead, burst fire, break, climb,
  flee), the Herons and Oxen on their routes with rear gunners, the train and lorries, the
  eight missions, the campaign, and the autopilot (dogfights, strafing runs, escorting, home).
  Where C's `&&` skips a call to the random generator, the BASIC nests `If`s (VB's `And`
  evaluates both sides), so the generator is called exactly as often.
- The picture: render.c's scene with the camera banking with the aeroplane (chase view swinging
  round after it, or the cockpit), the sky gradient and the earth tilted with the bank, the
  patchwork of fields with hedges, the river, the railway, no-man's-land and the trenches, the
  road, the aerodromes, hills, sheds, dumps, guns, balloons with their cables, the train and
  lorries, the biplanes in two levels of detail (a dot beyond), tracer, shell bursts, smoke,
  explosions and clouds; the HUD (objective, arrow, radar, gunsight, speed, height, throttle,
  gun heat, ammunition, damage) and the cockpit's panel; the briefing with its map, the result,
  the end of the campaign, the help pages, the palette.
- The thirteen effects, made at start-up with the same numbers as `game_sound_init` (Audio's
  amiga3d-style calls). Like the C, no music.

Changed:

- **Drawing** is Boing.Engine3D: the camera's bank is render.c's `xf` (`CamBank`), the models
  are drawn by the engine (the biplane through `DrawModelMF`: at its 16.16 position, with
  `a3_rot_ypr` >> 2, as render.c draws its quarter-unit model, so the chase view doesn't judder). The ground's flat pieces are
  kept in layers of world quads and handed to the engine with one `QuadsW` call a layer; they
  are made again only when the camera moves into another 400-unit cell (render.c makes them
  every frame). The view reaches 3200 units, as the C's on AmigaOS 4.
- **The picture is 320 x 256** (shown 2x); the C on AmigaOS 4 draws its polygons at 640 x 512.
- **High scores**: a table of eight, saved beside the program, with name entry after a campaign
  that makes it (the C keeps the best score in memory).
- **Text** is the Canvas's 6 x 9 font.
- **Keys**: M switches the effects, F9 the timing overlay. The AmigaBridge interface isn't
  ported (the tests drive the BASIC directly).

## Files

| File | |
|---|---|
| `AcePilot2.bbp` | the game: the form `ace.afg` + `ace.bas` |
| `ApCore.bas` | the war (ap_core.c), the autopilot and the state hash |
| `ApShell.bas` | the shell's 40 ms tick (game.c): explosions, smoke, the camera easing, flashes |
| `ApDraw.bas` | the scene on Engine3D, the HUD, the cockpit, the screens |
| `ApSound.bas` | the effects on Boing.Audio |
| `Trace.bbp`, `tools/trace.c`, `tools/trace.sh`, `tools/test.sh` | the host test against the C |
| `Bench.bbp` | console bench: the autopilot flies, every frame drawn off-screen |
| `tools/guest_shots.py` | the screenshots on a guest |

## Tests

- **Host (`make test`)**: `tools/test.sh` runs `Trace.bbp` in the VM, the VM with every loop
  JIT-compiled, and native; each must print `tests/trace.out`, the C original's output
  (`tools/trace.sh`). It flies the C test's long autopilot campaign (seed 1234, 20000 ticks,
  through six missions: its final hash is the C's `tests/vectors.h`, and the state hash is
  printed and compared every 1000 ticks) and a 4000-tick campaign from each of the eight
  missions: every kind of kill, ground target, flak, landing, failure and the win. Each line
  has the full state hash (every aeroplane, ground thing and bullet, the score and the random
  generator) and a hash of every event with its position.
- **Guest smoke run**: `BB_GUEST=m1b examples/common/tools/guest_game.py
  examples/ace_pilot2_bb/AcePilot2.bbp vm --smoke 400 --data RAM:bbg/examples/ace_pilot2_bb`.

## Performance

On the Mac (Apple M-series), `Bench.bbp --frames 3000 --mission 6` (the autopilot, every frame drawn on an off-screen
canvas): VM `logic 0.013 draw 0.063 ms/frame, 13037.1 fps;  polys/frame 136.9`; native `logic 0.002 draw 0.048 ms/frame, 19994.5 fps;  polys/frame 136.9`. The VM and native
builds give the same state and picture hashes.

The guest numbers (m1b: VM, JIT, native) and the guest screenshots follow in the next update.
