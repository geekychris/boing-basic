# Performance

`make bench` (tools/bench.py) runs every program in `bench/` in the VM (`boing run`) and as a
native build (`boing build`, host `cc -O2`). Where there is a hand-written C version of
the same algorithm (`bench/c/`), it runs that too. The script checks that the VM and native
builds print the same result. Times are the best of 3 wall-clock runs, in seconds; the
native times include ~0.01 s of process start-up. `tools/bench.py --scale N` multiplies
the work (use a smaller workload on the OS4 guest: `--scale 1` is sized for the Mac).

| benchmark | what it measures |
|---|---|
| int_loop | Integer/Long arithmetic, `\`, `Mod`, `And` in nested For loops |
| double_math | Double arithmetic and division |
| strings | `&`, `Mid$`, `Left$`, `Right$`, `InStr`, `Len`, `Asc` |
| arrays | fixed and dynamic 1-D Long arrays, a 2-D Double array |
| calls | ByVal/ByRef Sub and Function calls |
| fib | recursion |
| variants | Variant arithmetic |
| udt | fields of an array of `Type` records |
| objects | early-bound property/method calls, then late-bound (`Object`) ones |
| coll | `Collection` Add with keys, lookup, For Each, Remove |
| select | `Select Case` on integers and strings |
| fileio | `Print #` / `Line Input #` of a text file |
| sieve, nbody, fannkuch, mandelbrot | classic whole programs |

## Results

### macOS (Apple M-series, clang 21): VM, VM + arm64 JIT, native (2026-11-07)

`VM+JIT` is `boing run --jit` (docs/jit.md). The OS4 numbers (PPC JIT) follow when they
have been measured on the guest.

| benchmark | VM (s) | VM+JIT (s) | native (s) | VM/native | JIT/native | C (s) | native/C | same output |
|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| arrays | 0.213 | 0.106 | 0.046 | 4.6x | 2.3x | - | - | yes |
| calls | 0.080 | 0.076 | 0.015 | 5.3x | 5.1x | - | - | yes |
| coll | 0.122 | 0.122 | 0.119 | 1.0x | 1.0x | - | - | yes |
| double_math | 0.230 | 0.079 | 0.031 | 7.5x | 2.6x | 0.020 | 1.6x | yes |
| fannkuch | 0.103 | 0.045 | 0.027 | 3.8x | 1.7x | 0.016 | 1.7x | yes |
| fib | 0.066 | 0.068 | 0.010 | 6.5x | 6.7x | 0.007 | 1.4x | yes |
| fileio | 0.152 | 0.151 | 0.146 | 1.0x | 1.0x | - | - | yes |
| int_loop | 0.122 | 0.078 | 0.019 | 6.4x | 4.1x | 0.019 | 1.0x | yes |
| mandelbrot | 0.026 | 0.022 | 0.008 | 3.2x | 2.7x | 0.006 | 1.5x | yes |
| nbody | 0.319 | 0.167 | 0.025 | 12.8x | 6.7x | 0.013 | 2.0x | yes |
| objects | 0.153 | 0.159 | 0.030 | 5.0x | 5.2x | - | - | yes |
| select | 0.120 | 0.124 | 0.016 | 7.3x | 7.6x | - | - | yes |
| sieve | 0.119 | 0.050 | 0.027 | 4.4x | 1.9x | 0.012 | 2.2x | yes |
| strings | 0.224 | 0.224 | 0.118 | 1.9x | 1.9x | - | - | yes |
| udt | 0.089 | 0.054 | 0.010 | 9.2x | 5.6x | - | - | yes |
| variants | 0.309 | 0.307 | 0.195 | 1.6x | 1.6x | - | - | yes |
| glimmerfield | 0.294 | 0.222 | 0.058 | 5.1x | 3.8x | - | - | yes |
| glimmerfield_draw | 0.252 | 0.149 | 0.069 | 3.7x | 2.2x | - | - | yes |

`glimmerfield` and `glimmerfield_draw` are the real-world rows: bb-game's Glimmerfield
(`examples/glimmerfield/Bench.bbp`), 20000 frames of game logic, and 250 frames of logic plus
the renderer drawing into a `SoftCanvas` (a class holding the framebuffer as array fields). They
were 0.627 s and 0.979 s in the VM before the steps below marked *(Glimmerfield)*.

What changed in the VM (vs the baseline below):
- module variables used only by the main program are locals (fast slots);
- typed Integer/Long/Double expressions compile to 3-address register ops on frame slots
  (immediate and constant operands, no stack traffic, no tag checks), comparisons fused
  with the branch, `And` of comparisons tested one by one;
- 1-D/2-D array elements and UDT fields (of variables and of array elements) are loaded and
  stored by register ops; For loops on typed locals are register ops;
- threaded dispatch (computed goto, GCC/clang, also on PPC) for the register ops, one table
  for all opcodes; register temporaries are pre-tagged so ops store no type tags;
- frame set-up and tear-down fast paths for procedures without ByRef parameters;
- the JIT compiles loops made of register ops to machine code (docs/jit.md);
- `R_CALLS`: calls with ByVal Integer/Long/Double arguments taken from slots, result into a slot.

Late-bound calls (`objects`: VM 0.445 -> 0.181 s, native 0.147 -> 0.023 s): each call site
caches the member id per class (no name lookup per call), `bb_invoke_id` guards the call with
a cleanup entry instead of a setjmp frame, and on macOS/BSD all error frames use
`_setjmp` (plain `setjmp` saves the signal mask: two system calls). bb-game's
`o.PSet x, y, c` on an `Object`: native 207 -> 16 ns, VM 519 -> 70 ns per call.

Calls and the game (*(Glimmerfield)*):
- typed procedures whose locals are all scalars return through `R_RET` (no release loop, no
  stack-op dispatch); frames of plain procedures are set up by copying a per-procedure
  template of pre-tagged slots; unconditional jumps are register ops (fib 0.115 -> 0.060 s);
- Single is a register kind (its own temporaries and ops, computed in double and rounded with
  VB's range check, as the C back end does), so Single fields/arrays stay in register forms;
- conditions that are pure And / Or / Not trees of typed comparisons and Booleans are tested
  piece by piece by compare-and-branch ops (VB evaluates both sides, but nothing can tell);
- array fields of `Me` are register-form operands (and JIT-compiled), so class methods that
  loop over member arrays run like module code (glimmerfield_draw 0.979 -> 0.256 s);
- the JIT marks loop heads it cannot compile, so they no longer cost a lookup per back-edge;
  compiled loops are found through a per-offset table and entered straight from the For check
  (nbody's 4-iteration inner loops: VM+JIT 0.191 -> 0.168 s);
- `R_CALLS` also passes ByRef arguments (local scalar variables of the parameter's type) as
  references, and such procedures get the fast frame and return;
- small procedures are inlined: a Sub/Function with ByVal scalar parameters and scalar locals
  (up to ~160 AST nodes, no On Error/GoSub/labels/With/For Each/ReDim), defined in the same
  file, called from a procedure without On Error, is compiled into the caller with its locals
  in fresh slots. The inlined statements keep their own line numbers, so run-time error
  messages are the same as without inlining (`BOING_NO_INLINE=1` turns it off)
  (calls 0.136 -> 0.079 s);
- scalar fields of `Me` are register operands (`R_LDMF` / `R_STMF`, also in the JIT); class
  methods get the fast frame (early-bound `CALLM`) and the fast return, which drops `Me`
  itself (objects VM 0.219 -> 0.156 s). Native method calls on a receiver that is not a
  local now hold a reference for the call, as VB does (objects native 0.024 -> 0.030 s:
  correctness first; `Set g = Nothing` inside a method of g's object freed it mid-call);
- module-level (and Static) scalars are register operands (`R_LDG` / `R_STG`; bb-game's
  `g = g + 1` 7.9 -> 5.5 ns, 3.1 ns with the JIT);
- the JIT compiles Single arithmetic (load as double, VB's range check as an exit, store
  rounded: `lfs`/`stfs` on PPC), so loops over Single fields are no longer cut
  (glimmerfield VM+JIT 0.300 -> 0.222 s).

What changed in the native back end: array bounds failures go to a `noreturn` function, so
GCC/clang can keep element addresses in registers across statements (nbody 0.061 -> 0.027 s).

### macOS, baseline before VM work (2026-11-07)

| benchmark | VM (s) | native (s) | VM/native | C (s) | native/C | same output |
|---|---:|---:|---:|---:|---:|:---:|
| arrays | 1.080 | 0.080 | 13.5x | - | - | yes |
| calls | 0.383 | 0.017 | 23.2x | - | - | yes |
| coll | 0.149 | 0.144 | 1.0x | - | - | yes |
| double_math | 0.495 | 0.031 | 16.2x | 0.019 | 1.6x | yes |
| fannkuch | 0.416 | 0.032 | 12.8x | 0.016 | 2.1x | yes |
| fib | 0.187 | 0.013 | 14.7x | 0.007 | 1.7x | yes |
| fileio | 0.155 | 0.142 | 1.1x | - | - | yes |
| int_loop | 0.632 | 0.027 | 23.1x | 0.019 | 1.5x | yes |
| mandelbrot | 0.071 | 0.008 | 8.6x | 0.006 | 1.4x | yes |
| nbody | 1.624 | 0.064 | 25.2x | 0.013 | 4.9x | yes |
| objects | 0.448 | 0.141 | 3.2x | - | - | yes |
| select | 0.310 | 0.018 | 17.0x | - | - | yes |
| sieve | 0.971 | 0.039 | 25.2x | 0.012 | 3.2x | yes |
| strings | 0.207 | 0.118 | 1.8x | - | - | yes |
| udt | 0.546 | 0.030 | 18.4x | - | - | yes |
| variants | 0.280 | 0.187 | 1.5x | - | - | yes |

## Game benchmark

[Glimmerfield](../examples/glimmerfield/README.md) (bb-game) is an arcade game written to be
a real-world test: arrays of UDTs (96 crystals, 32 bullets, 16 wisps, 512 particles), integer
fixed-point maths and collision tests every frame, Single maths for the particles, small helper
functions called ~10 000 times a frame, a string HUD, and a renderer that draws through a canvas
object (late-bound calls). The console bench (`examples/glimmerfield/Bench.bbp`) lets the bot
play from seed 1987:

```
boing run [--jit] Bench.bbp --bench 20000            # logic only
boing run [--jit] Bench.bbp --bench 2000 --draw      # + renderer onto SoftCanvas (BASIC framebuffer)
```

`--draw` renders every frame onto `SoftCanvas.cls`, the Canvas methods implemented in BASIC on a
400x300 Long array (Bresenham lines, midpoint circles); "blit" copies it to a front buffer
(120 000 element copy). All builds print the same state and picture hashes.

### macOS (Apple M-series), main 9605f6f, ms per frame (best of 3)

| | logic | draw | blit | frame | fps |
|---|---:|---:|---:|---:|---:|
| VM | 0.014 | 0.441 | 0.489 | 0.950 | 1052 |
| VM --jit | 0.014 | 0.278 | 0.256 | 0.553 | 1809 |
| native | 0.002 | 0.108 | 0.135 | 0.243 | ~4100 |

How the VM got there (logic ms/frame; `--draw` frame ms/frame):

| main | change (bb-core) | logic | draw frame |
|---|---|---:|---:|
| 84ae15a | first VM | 0.053 | 3.25 |
| eea3c41 | late-bound calls without setjmp/strcasecmp per call | 0.030 | 3.72 |
| d6bdbd0 / db88308 | register ops incl. Single and member arrays, inlining of small helpers | 0.015 | 0.92 |
| 9605f6f | Me's fields in register ops, fast method frames | 0.014 | 0.95 (JIT 0.55) |

Slow paths the game found and how they ended up:

- UDT array field `a(i).x = a(i).x + a(i).vx`: 5 stack ops per access, 32 ns -> register ops, 6.5 ns.
- Late-bound method calls (every form-control call): macOS `setjmp` saving the signal mask
  (two syscalls) and a name lookup per call; 519 -> 96 ns VM, 207 -> 17 ns native.
- Single UDT fields fell back to stack ops (28 ns) -> Single register kind, 5.8 ns.
- Class member arrays (SoftCanvas's framebuffer) in register ops and the JIT: blit 2.0 -> 0.49 ms
  (JIT 0.26).
- Calls to small helpers (WrapL, DeltaPx, SinA, RandL): inlined (11 -> 5.8 ns per call).
- Still open: module-level scalars cost ~2.7x a local in the VM (7.9 vs 2.9 ns), and the JIT
  doesn't speed up the logic (it is call- and module-variable heavy).
- Lexer: `1000000# / 200000#` was read as a date literal (fixed in eea3c41).

### AmigaOS 4.1 (QEMU sam460ex)

Pending: guest runs of VM, JIT and native, and the real game on the Canvas control.
