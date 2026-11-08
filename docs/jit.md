# The Boing BASIC JIT

`boing run --jit prog.bas` (or `BOING_JIT=1`) compiles hot loops of the VM to machine code.
It is off by default. Backends: 32-bit PowerPC (AmigaOS 4, the target) and AArch64 (the
Mac, where the whole test suite runs with it).

## What gets compiled

The VM compiles statically typed code to *register ops* (opcodes `R_*`, see
`src/vm/bytecode.h`): 3-address Integer/Long/Double arithmetic on frame slots, compare and
branch, For loops, 1-D/2-D array elements, UDT fields, ByRef parameter access, `Sqr`. A
*region* is a run of consecutive register ops. A loop whose body consists only of these ops
(which is what typed numeric loops compile to) is one region. Arrays may be locals,
globals or array fields of `Me` (class methods). A region ends at a call (`R_CALLS`), a
return, `Sqr` on a backend without a square root instruction (PPC). Single arithmetic is
compiled as double arithmetic followed by VB's range check (an exit) and a rounding store
(`lfs`/`stfs` on PPC, `fcvt` on arm64), exactly what the interpreter and the C back end do.
Module-level scalars and scalar fields of `Me` are operands too.
A loop body cut by a call or `Sqr` is compiled in pieces: from the loop head to the call,
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
