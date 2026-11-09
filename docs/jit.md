# The Boing BASIC JIT

`boing run --jit prog.bas` (or `BOING_JIT=1`) compiles hot loops of the VM to machine code.
It is off by default. Backends: 32-bit PowerPC (AmigaOS 4, the target) and AArch64 (the
Mac, where the whole test suite runs with it).

## What gets compiled

The VM compiles statically typed code to *register ops* (opcodes `R_*`, see
`src/vm/bytecode.h`): 3-address Integer/Long/Double arithmetic on frame slots, compare and
branch, For loops, 1-D/2-D array elements, UDT fields, ByRef parameter access, `Sqr`,
`Int`/`Fix` of a Double, Double to Long/Integer (banker's rounding, by adding and subtracting
2^52), `MulShr` with a constant count (`mulhw`/`smull`), `MulDiv` (in double: exact while
|a * b| < 2^53, else an exit to the interpreter). A
*region* is a run of consecutive register ops. A loop whose body consists only of these ops
(which is what typed numeric loops compile to) is one region. Arrays may be locals,
globals or array fields of `Me` (class methods). A region ends at a call (`R_CALLS`), a
return, `Sqr` on a backend without a square root instruction (PPC). Single arithmetic is
compiled as double arithmetic followed by VB's range check (an exit) and a rounding store
(`lfs`/`stfs` on PPC, `fcvt` on arm64), exactly what the interpreter and the C back end do.
Module-level scalars and scalar fields of `Me` are operands too.
A loop head's region is the whole loop, up to its last back-edge: what the JIT cannot compile
inside it (a call, a stack op on a rarely taken path, `Sqr` without fsqrt) becomes an exit to
the interpreter at that op, which re-enters compiled code at the next back-edge. A region that
is left from the middle more often than not (after 32 entries) is switched off, so a loop whose
hot path keeps leaving compiled code runs in the interpreter, never slower than without the
JIT. `BOING_JIT_STATS=1` prints the entries per region at exit. Without a back-edge (e.g. at a
call's return point), a run of compilable ops is compiled; a loop body cut by a call or `Sqr` is compiled in pieces (each piece that is not a whole loop
needs at least `BOING_JIT_MINOPS` register ops; the default, 1000, means whole loops only, which measured best on the m1 guest (8 was the earlier default): on the QEMU guest every entry into
and exit from compiled code is expensive, and short pieces between calls made call-heavy code
slower): from the loop head to the call,
and from the instruction after the call (a *resume point*: the VM looks there for compiled
code when the call returns or after it computed `Sqr`) to the back-edge, which continues in
the loop head's code. Compiled loops are also entered straight from their `For` check. A
loop head or resume point whose region cannot be compiled is marked, so it then costs one
byte test.

- Each backward branch counts its target. At `BOING_JIT_THRESHOLD` (default 2) the region
  starting there is compiled, if it contains its own back-edge.
- The compiled code is a leaf function `int32_t fn(bb_jitctx *)`. It works directly on the
  frame's slots (`L`), the globals (`G`) and the constants (`K`). It returns the bytecode
  offset where the interpreter continues: the end of the region, or a branch target outside
  it. When that target is another hot loop head (an outer loop), the VM goes straight into
  that loop's code.
- Every slow path leaves at the op that needs it, *before* the op has any effect: Integer or
  Long overflow, division by zero, Double overflow, a `Long` `\ -1`, an unallocated array or an
  index out of range, `Sqr` of a negative number, and the Ctrl-C poll counter running out.
  The interpreter then executes that op itself and raises the VB error, or polls, exactly
  as without the JIT. The JIT therefore never has to raise errors or know about frames.

Typed slots always hold their tag, so the JIT reads and writes only the 8-byte payload
(`u` at offset 8 of a `bb_value`). Array access reads `bb_array` fields (ndims, bounds,
data) with `offsetof`, so the code matches the runtime it is built with.

## Backends

`src/vm/jit.c` is the translator (region scan, one function per op, exits, cache, code
memory). It calls a small assembler interface (`JBackend` in `jit.h`: loads/stores,
32-bit integer ops with overflow branches, compares, double ops, poll). The backends are:

- `jit_ppc32.c`: SysV PPC32. r3 = context, r4/r5/r6 = L/G/K, r7-r11 integers, r12/r14/r15
  pointers, f0-f4 doubles; a 32-byte frame saves r14-r16. Signed overflow uses the `o.`
  forms after clearing XER (`bso`). It uses only instructions every 32-bit PowerPC has:
  int-to-double goes through the 2^52 trick in memory, there is no `fsqrt` (G3/G4 lack it),
  and never `dlmzb`. Code memory comes from `AllocVecTags(AVT_Type, MEMF_EXECUTABLE)` and
  is made visible with `CacheClearE(CACRF_ClearD | CACRF_ClearI)`.
- `jit_arm64.c`: macOS (`MAP_JIT`, `pthread_jit_write_protect_np`,
  `sys_icache_invalidate`) and Linux.

`boing jitdump prog.bas out.bin [ppc|arm64]` writes every compilable region of a program
with either backend, for checking the encodings on any host:
`ppc-amigaos-objdump -D -b binary -m powerpc -EB out.bin`.

## On the QEMU guest

`--jit` on AmigaOS 4 first times a walk over 48 memory pages (~3 ms). Under QEMU's sam460ex a
TLB refill costs ~1.2 us and the JIT measured slower than the VM in every amiga3d port
(bb-g-more: Sphere Siege 17.7 -> 9.8 fps), so when refills cost more than 200 ns the JIT stays
off for the whole program; real machines refill in nanoseconds and keep it.
`boing run --jit -v` prints the decision once on stderr (`jit: off: TLB refills cost 1180 ns
(an emulator such as QEMU); BOING_JIT=force uses it anyway`). `--jit-force` or `BOING_JIT=force`
skips the test (tools/os4-core-tests.sh uses it to test the PPC backend on the guest).


The PPC JIT passes the test suite on the guest (every loop compiled) and speeds up arithmetic
loops 2-3x there. On field-heavy game code (Glimmerfield) it compiles almost everything and is
2x faster on the Mac, but about 40 % slower than the interpreter under QEMU's TCG, which charges
more per guest branch and memory access than the interpreter's dispatch saves. Real PowerPC
hardware is expected to behave like the Mac but is untested. The JIT is opt-in (`--jit`).

m1's unloaded guest (bb-game, Glimmerfield, ms/frame; hashes identical everywhere):

| | native | VM | VM+JIT (MINOPS 8) | VM+JIT (whole loops, default) |
|---|---:|---:|---:|---:|
| bench logic | 0.152 | 0.879 | 0.669 | 0.586 |
| bench canvas draw | 1.47 | 7.95 | 9.32 | 8.73 |
| form game, fps | 354-365 | 88.4 | 75.4 | 78.7 |

The JIT gains 33 % on the logic there but still loses 10 % on the drawing (Render.bas: loops of
late-bound Canvas calls with array arguments and small helper calls), so the game as a whole is
slower with it. The local guest, more loaded, showed the JIT slower on the logic as well.

## Testing

```
make test                                                        # runs every test with the JIT forced on as well
BOING_JIT=1 BOING_JIT_THRESHOLD=1 NATIVE=0 sh tests/run.sh      # Mac: every region compiled at once
RUNFLAGS=--jit tools/os4-core-tests.sh                           # OS4 guest
```

The JIT must give byte-identical output to the interpreter on the whole suite. `make bench`
has a VM+JIT column (docs/performance.md).

`BOING_JIT_TRACE=1` prints every region compiled. `BOING_JIT_LOG=file` writes each compile
(code address, size) and the first calls into compiled code (entry, context, return pc) to a
file, flushed per line, so the log survives a crash (for the guest, which has no debugger
attached). `BOING_JIT_NOSQRT=1` makes the host JIT
compile as for a CPU without `fsqrt` (the PPC region shapes), to test them on the Mac:
`BOING_JIT_NOSQRT=1 make test`.
