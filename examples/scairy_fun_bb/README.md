# ScAIry Fun (Boing BASIC)

A self-driving car game in Boing BASIC: a port of amiga_mcp's
[`examples/scairy_fun`](https://github.com/geekychris/amiga_games/tree/main/scairy_fun)
(C with its own road renderer, on the amiga3d engine's maths).

You ride in a car that drives itself. Points come from the distance it drives **on autopilot**,
multiplied by how long it has stayed on (up to x8). The autopilot is good, but it has blind
spots: take the wheel just before it gets something wrong, then hand it back. Take over when it
was right all along and it tells you "I had that."

![Levee Road on autopilot, on the guest](screenshots/os4-levee.png)


| Key | |
|---|---|
| Left / Right | steer (takes over) |
| Down | brake (takes over) |
| Up | accelerate (when driving yourself) |
| Space | autopilot on / off (on only near a lane centre); starts the game |
| V or C | chase / cockpit view |
| P | pause |
| Help / H | the rules (three pages; the title shows them too) |
| M / S | music / effects on and off |
| F9 | timing overlay |
| Esc | title / quit |

The four routes are the C's: **Levee Road** to the marina (autopilot v1.0: floods, old lane
lines), **Rush Hour** to the office (v2.0: overpass shadows, a coned-off lane, an ambulance,
debris), **Mountain Pass** to the ski lodge (v3.0: the low sun, fallen rocks, old lines) and
**Flooded Town** home (v4.0: flooded streets, a detour through the oncoming lane, an ambulance,
a phantom shadow). Damage comes off your insurance cover; at 0 the policy is cancelled.

| | |
|---|---|
| ![Mountain Pass: the low sun blinds the autopilot](screenshots/os4-mountain.png) | ![Flooded Town from the cockpit](screenshots/os4-town.png) |
| ![The title](screenshots/os4-title.png) | ![The rules, page 3](screenshots/os4-help.png) |


## What is the same, what changed

Kept from the C original:

- **The simulation, exactly.** `ScCore.bas` is `track.c` and `world.c` line for line: the four
  routes' sections built into 8 m segments with their hazards, the car (steering, the bends
  pushing it out, aquaplaning, the guardrails, the river and the embankment, the tow truck),
  the autopilot (its plan, lane changes, the cyclist, what it sees, the phantom brake at an
  overpass, being blinded by the sun, the old lane lines it follows, its comments), traffic,
  the tailgating truck, the ambulance and its ticket, cones, collisions, scoring, the
  multiplier, good catches and needless grabs, arrival, the software update and the next route.
  Where C's `&&` skips a call to the random generator, the BASIC nests `If`s.
- The picture: render.c's road (each segment a cross-section of 8 points: levee and river,
  embankment, rock wall, cliff and valley, median, town pavement, canal), the lines (and the
  old ones), rails, the chequered finish, the autopilot's cyan path, cones, scenery (trees,
  pines, poles, boulders, lamps, houses, blocks), the overpass and the finish gantry, every
  model from models.c with its own shading rule, the low sun washing the palette towards white,
  the painted dusk all the way round (`assets/horizon.png`), the AI's brackets (and the
  imagined red one), the cockpit with its steering wheel, the messages, the HUD with the
  autopilot's view from above, the intro, arrival, update, game-over and win boxes, the title
  painting, the demo and the three rules pages in turn.
- The sound: "Autopilot Lounge" (`scairy.mod`), the ten effects made at start-up with the same
  numbers as `game_sound_init` (the scrape's halved groups too), and the AI's 19 spoken lines
  (`scairy.voc`, Kokoro's bf_emma), split into `sc_voice_NN.raw` by `tools/make_assets.py`.

Changed:

- **Drawing** is Boing.Engine3D, one pass a frame. Each segment's strips (verges, road, lines,
  rails) and scenery are worked out once, when it comes into view, and kept in a ring of 64 slots
  (made again every 8 frames where water moves); each frame they go to the engine with one
  `QuadsW` call at the depth of the segment's far edge, and every model standing on a segment
  sorts just in front of it, so the painter's order by segment is render.c's. The engine draws
  the models (render.c's add_model) with the same culling and face order.
- **The picture is 320 x 256** (shown 2x); the C on AmigaOS 4 draws at 640 x 512.
- **High scores**: a table of eight, saved beside the program, with name entry when a game ends
  (cancelled or home).
- **Text** is the Canvas's 6 x 9 font.
  The autopilot's view in the HUD draws its label ("AI" / "OFF") last, over the dotted road
  edges, as render.c does; the left edge's dots run just beside the "I", in the C too.
- **Keys**: Space also starts (the C's fire); M and S switch the music and effects, F9 the
  timing overlay. The AmigaBridge interface (the tunables, the scene hooks) isn't ported.

## Files

| File | |
|---|---|
| `ScairyFun.bbp` | the game: the form `scairy.afg` + `scairy.bas` |
| `ScCore.bas` | the routes and the simulation (track.c, world.c) and the state hash |
| `ScShell.bas` | the shell (game.c): the world's tick, the title cycle, which screen to draw |
| `ScDraw.bas` | the road on Engine3D, the models, the sky, the overlays, the HUD, the screens |
| `ScSound.bas` | music, effects and the voice on Boing.Audio |
| `Trace.bbp`, `tools/trace.c`, `tools/trace.sh`, `tools/test.sh` | the host test against the C |
| `Bench.bbp` | console bench: the perfect autopilot drives, every frame drawn off-screen |
| `tools/make_assets.py` | the pictures, the music and the voice from the C original's files |
| `tools/guest_shots.py` | the screenshots on a guest |

## Tests

- **Host (`make test`)**: `tools/test.sh` runs `Trace.bbp` in the VM, the VM with every loop
  JIT-compiled, and native; each must print `tests/trace.out`, the C original's output
  (`tools/trace.sh`, which uses a state hash of the whole world: the car, the autopilot's plan
  and state, every object, the hazards, the score). It drives the title's demo, the perfect
  autopilot along each route to the destination, the shipped autopilot hands-off along each
  route (failing its hazards: the river, the policy cancelled), and random hands on each route
  (takeovers, needless grabs, crashes). The state hash is compared every 1000 frames.
- **Guest smoke run**: `BB_GUEST=m1c examples/common/tools/guest_game.py
  examples/scairy_fun_bb/ScairyFun.bbp vm --smoke 400` (real time with the music, the effects and
  the voice through AHI). **Screenshots**: `tools/guest_shots.py OUTDIR [vm] [names]` (one lock
  ticket each; the ones here are from m1b).

## Performance

`ScairyFun --bench 500`: the perfect autopilot drives route 1 in the form's window, frames back
to back, every frame drawn (the road through Engine3D, about 400 polygons, the HUD through the
Canvas) and shown. On **m1c** (QEMU sam460ex on an unloaded Mac), ms per frame:

| | logic | draw | blit | frame | fps |
|---|---:|---:|---:|---:|---:|
| VM (`boing run`) | 7.61 | 24.74 | 3.39 | 36.09 | **27.7** |
| VM `--jit` | 9.47 | 27.54 | 3.31 | 40.75 | **24.5** |
| native (`boing build --target os4`) | 0.74 | 6.88 | 3.21 | 11.03 | **90.7** |

All three end in the same state hash (1B758A86). Played in real time (`--smoke 400`: the form's
timer, the music, the effects and the voice through AHI) the VM shows **29.0 fps** on m1b (logic
4.5, draw 23.4, blit 3.4 ms a frame).

Getting there: the first port drew each segment in its own engine pass and worked out every
strip, tree and lane dot each frame: 16.3 fps in the VM. Now each segment's strips and scenery
are made once and kept (one engine pass a frame), the AI view's dots are one `PSetMany`, and the
object loops test for an empty slot first; the picture and the hashes are unchanged. The form's
timer used to start its 20 ms again only when the frame was done (16.9 fps in real time); it
keeps a fixed timeline since c791c7a. The JIT doesn't help
under QEMU (see docs/performance.md); the plain VM is the one to use.

On the Mac (Apple M-series), `Bench.bbp --frames 3000 --route 1`: VM `logic 0.019 draw 0.102
ms/frame, 8285.8 fps`; native `logic 0.002 draw 0.065 ms/frame, 14793.8 fps` (388.5 polys a
frame); the same state and picture hashes (8F4A00E0, 1942729246).
