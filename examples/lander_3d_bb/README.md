# Lander 3D (Boing BASIC)

The lunar lander in three dimensions, in Boing BASIC for AmigaOS 4.1: a port of
[Lander 3D](../../../amiga_mcp/examples/lander_3d/README.md) from amiga_mcp's examples
(C, on the amiga3d engine), itself a port of the browser game. The simulation, levels,
scoring and look are the original's, the simulation bit for bit; the 3D is drawn by the
[Engine3D](../../docs/engine3d.md) object (the amiga3d engine in C), the music and
effects are played by the [Audio](../../docs/audio.md) object.

You start high above generated terrain, moving, with a fixed amount of fuel. The main
engine pushes along the lander's own up direction: tip it to move sideways, level it to
stop, and keep enough thrust on to stop gravity winning. Three pads are somewhere below:
a big green one worth x1, a yellow x2 and a small magenta x5 on rougher ground. Touch down
with every leg on a pad, slowly (2.5 m/s on the Moon, 3 on Mars, 1.5 on the asteroid), not
sliding (1.5, 1.8, 1.0 m/s) and nearly level (10 degrees, 12 on the asteroid). The HUD shows
each reading green within its limit, amber close to it and red past it; the arrow at the
top points to the nearest pad. A landing scores (100 + softness + fuel left) x the pad; a
safe landing off the pads scores 25; anything else costs a ship. **Moon**: 1.62 m/s2.
**Mars**: 3.71 m/s2 and a gusting wind. **Asteroid**: hardly any gravity, a weak engine,
rough ground. **Tour** takes them in turn. Each level starts higher, faster and farther
out, with smaller pads. Every level can be landed: the autopilot flies it first, and the
tank gets 30 % more than that flight used.

| Key | |
|---|---|
| Space / J | full thrust |
| Q / E | steady throttle down / up (10 % steps) |
| Up / W, Down / S | tip forward, back |
| Left / A, Right / D | tip left, right |
| P | pause |
| B | the autopilot takes over (and gives back) |
| Help / H | the rules (two pages) |
| M / N | music / sound effects on or off |
| F1 | timing overlay |
| F2 | the high scores (on the title) |
| Left / Right, Up / Down on the title | the world or the tour, the starting level |
| Esc | title / quit |

Options: `--bench N`, `--attract`, `--perf`, `--log`, `--level N`, `--start WORLD`, `--ships N`,
`--place`, `--win N`, `--quiet`, `--dir PATH` (see the top of `lander.bas`).

## Screenshots

On AmigaOS 4.1 (the m1c QEMU sam460ex guest), native build: the title painting, and the
autopilot flying the Moon, Mars (with its wind) and the asteroid:

| | |
|---|---|
| ![The title](docs/guest-title.png) | ![The Moon](docs/guest-moon.png) |
| ![Mars](docs/guest-mars.png) | ![The asteroid](docs/guest-asteroid.png) |

The screens as `tools/guest_flow.py` plays them with injected keys: help, a landing on
the x1 pad, flying on to level 2, a crash, the name entry and the saved table:

![Help, landing, level 2, crash, name entry, high scores](docs/guest-flow.png)

## Files

| file | |
|---|---|
| `Lander3D.bbp` | the game: a form project (startup form `lander`) |
| `lander.afg`, `lander.bas` | the form, "Lander 3D (Boing BASIC)" (a 640 x 512 Canvas and a 40 ms Timer) and its code-behind: keys, the screens, `--bench N`, `--log` |
| `LdCore.bas` | the simulation (`ld_core.c`): worlds, terrain, pads, the craft, touchdown, the autopilot, the level check, and at its top the amiga3d engine's integer maths (A3Fix's names, integer-only, so they inline). No drawing, no OS calls |
| `LdGame.bas` | the game around it (`game.c`): title demo, levels, ships, outcomes, scoring |
| `LdDraw.bas` | the picture (`render.c`) through Engine3D: sky, ground grid, pads, lander, exhaust, shadow, HUD, title, help, high scores |
| `LdSound.bas` | the module and the six effects through the Audio object |
| `art/*.png` | the original's title painting and skies (`tools/make_art.py` converts its `.img` files) |
| `lander_3d.mod` | the original's music, "Quiet Descent" |
| `Bench.bbp`, `BenchMain.bas` | the console bench (an off-screen canvas, the Mac too) |
| `bench/` | micro benchmarks of the simulation's pieces |
| `tools/trace.c`, `trace.sh` | the C original's flights, the reference for the tests |
| `tools/guest.py`, `guest_flow.py` | runs on an AmigaOS 4 agent guest (m1b, m1c or local; never the user's m1): the bench, screenshots, the screens played with injected keys; `guest.py cleanup` after an interrupted run |
| `ArtTest.bbp` | guest check: the pictures and the music without a window |

## What is the same, and what changed

The same:

- The simulation is `ld_core.c` line for line in BASIC, in the same 16.16 fixed point
  with the same integer trigonometry, square roots and random numbers: a seed builds the
  same terrain and pads, and a flight (the autopilot's or a pilot's) gives the same state
  hash at every step as the C. The worlds, the level parameters, the touchdown rules, the
  scoring, the autopilot and the level check are the original's.
- The game flow (`game.c`): the title with the painting in turn with the autopilot's demo,
  four 1/100 s steps a 40 ms frame, three ships, the result screen, the tour.
- The picture (`render.c`): the camera, the terrain window drawn to the horizon with the
  map's mirror image past its edges, each cell in render.c's slope pen, the pads sorted at
  their nearest point, the lander model, exhaust and shadow, the painted skies drifting
  with the camera, the plain fading to the horizon, the HUD, the compass and wind arrow,
  the help pages. The 32-pen palettes are the original's.
- The sounds: the six effects are made sample for sample as amiga3d's `a3_tone` /
  `a3_noise` make them (the test checks a checksum of the samples), and the module is the
  original's.

Changed:

- **High scores** (new): the eight best scores with names, saved in `lander_3d.scores`
  beside the program; a new one asks for a name after the game. "BEST" on the title is
  the top score. F2 shows the table from the title.
- **Keys** (new): B hands the lander to the autopilot and back (the original does that
  through its AmigaBridge hook), M and N switch the music and effects, Up/Down on the title
  choose the starting level, F1 shows the timing. The help's second page lists them.
- **The level check runs 10 autopilot steps a frame**, not 150: in the interpreter a step
  costs more than on a 68k. Its result (and the tank top-up) is the same, it just arrives
  later into the level (a typical check is 3000-5000 steps: 12-20 s) instead of within a second or two.
- **The ground**: the engine draws a grid of the map with 32 mirrored cells round it
  (the original mirrors without end), the cells within 30 cells of the camera that are in
  view (the original: a 41 x 41 window ahead of the craft). Past that, the plain, as in
  the original.
- No AmigaBridge interface (its variables and hooks); the tests use `--log`, `--bench`
  and the window's state instead.
- The demo also flies behind the name entry and the high scores.

## Determinism and tests

`tests/programs/lander_3d` flies thirteen levels (all three worlds, levels 1 to 7, the
autopilot, scripted pilots with and without the attitude assist, crashes and off-pad
landings), runs three level checks and makes the effects; every line, hashes included,
must equal what `tools/trace.sh` prints from the C original. `tests/programs/lander_3d_draw`
draws 1500 frames of the tour and the other screens through Engine3D on an off-screen
canvas and compares picture hashes. Both run in the VM, with the JIT and natively
(`make test`).

On the guest, `tools/guest_flow.py` plays the screens with injected keys (title, both help
pages, flying, an autopilot landing, a crash, game over, the name entry, the saved table,
quit) and takes the screenshots above.

## Performance

`Lander3D --bench N` lets the autopilot fly the tour for N frames as fast as it can, drawing
every frame (with the timing overlay), and prints the time per frame and the state hash.
On the m1c agent guest (QEMU sam460ex on m1.local, a clone of the m1 guest; 200 frames
VM/JIT, 500 native; ms per frame):

| | logic | draw | blit | fps |
|---|---:|---:|---:|---:|
| VM (`boing run Lander3D.bbp --bench 200`) | 10.7 | 13.3 | 1.7 | **38.4** |
| VM with `--jit` | 15.5 | 14.8 | 1.7 | 30.8 |
| native (`boing build`, `Lander3D --bench 500`) | 1.1 | 12.5 | 2.3 | **62.2** |

(The JIT is slower here: the frame is call-heavy, see docs/jit.md. On m1b, before the
horizon became one `FillGradient` call: VM 31.7, JIT 28.9, native 70.8 fps.)

The state hash after the same number of frames is the same in all three (and on the Mac).
"logic" is four simulation steps a frame plus ten steps of the level check; "draw" is about
800 polygons through Engine3D (the ground grid, pads, lander), the sky picture and the HUD.
The Mac's VM does the same frame in 0.06 + 0.3 ms.

What it took in the VM on the guest (a simulation step: 3650 us at first, 440 us now):

- `CDbl()` expressions (examples/common/A3Fix.bas computed FMUL, FDIV and the angles through
  Doubles) went through a Variant builtin call: ~29 us each on the guest, 0.04 us on the Mac.
  bb-core made `Int`/`Fix`/`CDbl` typed and added `MulShr` / `MulDiv`, which the game uses for
  FMUL (`MulShr(a, b, 16)`) and FDIV (`MulDiv(a, 65536, b)`); the rest of the maths is
  integer-only (`Shl` / `ShrA` / `ShrL`, 16-bit partial products).
- A call to a procedure taking a Double (`ISqrtD(d)`) cost ~25 us inside `FHypot`; inlined, the
  length takes 3.8 us.
- The maths helpers live in `LdCore.bas` beside the simulation, so the compiler inlines them.
- Every VM call on the guest is expensive in a way the Mac doesn't show (the PowerPC 460's
  software-refilled TLB under QEMU; see docs/performance.md), so the level check runs 10 steps
  a frame, and the horizon's plain is one Engine3D `FillGradient` call.
