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
| arrays | 0.248 | 0.112 | 0.050 | 4.9x | 2.2x | - | - | yes |
| calls | 0.211 | 0.231 | 0.021 | 9.9x | 10.8x | - | - | yes |
| coll | 0.191 | 0.162 | 0.160 | 1.2x | 1.0x | - | - | yes |
| double_math | 0.212 | 0.097 | 0.063 | 3.4x | 1.6x | 0.022 | 2.9x | yes |
| fannkuch | 0.115 | 0.065 | 0.030 | 3.9x | 2.2x | 0.018 | 1.6x | yes |
| fib | 0.119 | 0.121 | 0.010 | 11.3x | 11.5x | 0.008 | 1.3x | yes |
| fileio | 0.168 | 0.168 | 0.156 | 1.1x | 1.1x | - | - | yes |
| int_loop | 0.137 | 0.084 | 0.021 | 6.4x | 3.9x | 0.020 | 1.1x | yes |
| mandelbrot | 0.028 | 0.028 | 0.009 | 3.2x | 3.2x | 0.006 | 1.5x | yes |
| nbody | 0.369 | 0.217 | 0.029 | 12.9x | 7.6x | 0.013 | 2.1x | yes |
| objects | 0.445 | 0.458 | 0.147 | 3.0x | 3.1x | - | - | yes |
| select | 0.129 | 0.141 | 0.017 | 7.5x | 8.2x | - | - | yes |
| sieve | 0.130 | 0.054 | 0.029 | 4.6x | 1.9x | 0.013 | 2.2x | yes |
| strings | 0.226 | 0.227 | 0.127 | 1.8x | 1.8x | - | - | yes |
| udt | 0.102 | 0.059 | 0.011 | 8.9x | 5.2x | - | - | yes |
| variants | 0.309 | 0.325 | 0.217 | 1.4x | 1.5x | - | - | yes |

Real-world check: `examples/glimmerfield/Bench.bbp` (bb-game's game logic, 2000 frames):
VM 0.032 ms/frame, native 0.003 ms/frame; VM, JIT and native print identical game state.

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
