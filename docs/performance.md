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
| calls | 0.079 | 0.082 | 0.017 | 4.8x | 5.0x | - | - | yes |
| coll | 0.122 | 0.122 | 0.118 | 1.0x | 1.0x | - | - | yes |
| double_math | 0.242 | 0.079 | 0.030 | 8.2x | 2.7x | 0.019 | 1.6x | yes |
| fannkuch | 0.096 | 0.045 | 0.026 | 3.6x | 1.7x | 0.016 | 1.7x | yes |
| fib | 0.063 | 0.063 | 0.010 | 6.2x | 6.2x | 0.007 | 1.5x | yes |
| fileio | 0.156 | 0.153 | 0.147 | 1.1x | 1.0x | - | - | yes |
| int_loop | 0.116 | 0.079 | 0.019 | 6.1x | 4.1x | 0.019 | 1.0x | yes |
| mandelbrot | 0.027 | 0.022 | 0.008 | 3.2x | 2.7x | 0.005 | 1.5x | yes |
| nbody | 0.315 | 0.168 | 0.027 | 11.6x | 6.2x | 0.013 | 2.2x | yes |
| objects | 0.219 | 0.219 | 0.023 | 9.5x | 9.5x | - | - | yes |
| select | 0.122 | 0.127 | 0.016 | 7.4x | 7.7x | - | - | yes |
| sieve | 0.113 | 0.048 | 0.027 | 4.2x | 1.8x | 0.012 | 2.2x | yes |
| strings | 0.229 | 0.228 | 0.121 | 1.9x | 1.9x | - | - | yes |
| udt | 0.089 | 0.054 | 0.010 | 9.4x | 5.7x | - | - | yes |
| variants | 0.308 | 0.314 | 0.198 | 1.6x | 1.6x | - | - | yes |
| glimmerfield | 0.307 | 0.298 | 0.060 | 5.1x | 4.9x | - | - | yes |
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
  (calls 0.136 -> 0.079 s).

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
