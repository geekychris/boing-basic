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

### macOS (Apple M-series, clang 21), baseline before VM work (2026-11-07)

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
