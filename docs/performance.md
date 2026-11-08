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
| arrays | 0.246 | 0.106 | 0.048 | 5.1x | 2.2x | - | - | yes |
| calls | 0.185 | 0.195 | 0.015 | 12.7x | 13.3x | - | - | yes |
| coll | 0.123 | 0.126 | 0.120 | 1.0x | 1.1x | - | - | yes |
| double_math | 0.251 | 0.078 | 0.030 | 8.4x | 2.6x | 0.019 | 1.6x | yes |
| fannkuch | 0.106 | 0.057 | 0.027 | 3.9x | 2.1x | 0.017 | 1.6x | yes |
| fib | 0.115 | 0.116 | 0.010 | 11.0x | 11.1x | 0.007 | 1.5x | yes |
| fileio | 0.154 | 0.154 | 0.149 | 1.0x | 1.0x | - | - | yes |
| int_loop | 0.133 | 0.080 | 0.021 | 6.5x | 3.9x | 0.019 | 1.1x | yes |
| mandelbrot | 0.027 | 0.027 | 0.008 | 3.2x | 3.2x | 0.006 | 1.5x | yes |
| nbody | 0.355 | 0.202 | 0.025 | 13.9x | 7.9x | 0.013 | 2.0x | yes |
| objects | 0.181 | 0.187 | 0.023 | 7.8x | 8.1x | - | - | yes |
| select | 0.127 | 0.134 | 0.017 | 7.4x | 7.8x | - | - | yes |
| sieve | 0.134 | 0.050 | 0.030 | 4.4x | 1.6x | 0.012 | 2.4x | yes |
| strings | 0.218 | 0.220 | 0.127 | 1.7x | 1.7x | - | - | yes |
| udt | 0.099 | 0.057 | 0.010 | 9.4x | 5.4x | - | - | yes |
| variants | 0.295 | 0.288 | 0.189 | 1.6x | 1.5x | - | - | yes |

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

Late-bound calls (`objects`: VM 0.445 -> 0.181 s, native 0.147 -> 0.023 s): each call site
caches the member id per class (no name lookup per call), `bb_invoke_id` guards the call with
a cleanup entry instead of a setjmp frame, and on macOS/BSD all error frames use
`_setjmp` (plain `setjmp` saves the signal mask: two system calls). bb-game's
`o.PSet x, y, c` on an `Object`: native 207 -> 16 ns, VM 519 -> 70 ns per call.

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
