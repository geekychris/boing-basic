# Exercise 9: Faster with C

**Goal:** make a program faster by moving its busiest work into C, first with a plain C
function, then with an extension class of your own.

**You will learn:**

- how to time a part of a program with `TimerMs`;
- how to call a C function with `Declare ... Lib "C"` and `CSource=`;
- how to write an extension in C: a `.bbx` descriptor and a class with methods and properties;
- why the number of calls between BASIC and C matters;
- how to run such a program in the interpreter with `boing vm`.

You need a C compiler: the AmigaOS 4 SDK's GCC on the Amiga (it also does native builds), or
`cc` on macOS and Linux. Read [Extending Boing BASIC](../20-extending.md) first, or alongside.

The finished program is `examples/book/ex09-extending/Sieve.bbp`.

## Step 1: the program in BASIC

The sieve of Eratosthenes counts the prime numbers up to a limit: cross out every multiple of
2, then of 3, of 5 and so on; the numbers left are the primes. In BASIC:

<!-- run -->
```basic
' sieve.bas - step 1: counting primes with the sieve of Eratosthenes, all in BASIC
Function CountPrimes(ByVal n As Long) As Long
    Dim composite() As Boolean, i As Long, j As Long, count As Long
    ReDim composite(n)
    For i = 2 To n
        If Not composite(i) Then
            count = count + 1
            If i <= n \ i Then              ' i * i would overflow a Long for big i
                For j = i * i To n Step i
                    composite(j) = True
                Next
            End If
        End If
    Next
    CountPrimes = count
End Function

Sub Main()
    Dim t As Double
    t = TimerMs()
    Print "Primes up to 1000000:"; CountPrimes(1000000)
    If Command() = "--time" Then Print "BASIC took "; Format(TimerMs() - t, "0"); " ms"
End Sub
```

```output
Primes up to 1000000: 78498 
```

Run it with `boing run sieve.bas --time` to see how long it takes. `TimerMs()` is a clock in
milliseconds; the difference of two readings is the time between them.

Notice the `If i <= n \ i` test: for `i` above 46340, `i * i` is more than a `Long` can hold,
and the program would stop with an overflow error.

## Step 2: the sieve in C

The inner loops are pure arithmetic: exactly the kind of work C does fastest. Write the whole
function in C, in a file `primes.c` beside the program:

```c
/* primes.c - the same sieve in C, called with Declare ... Lib "C" */
#include <stdint.h>
#include <stdlib.h>

int32_t count_primes(int32_t n)
{
    char *composite;
    int32_t i, j, count = 0;
    if (n < 2) return 0;
    composite = calloc((size_t)n + 1, 1);
    if (!composite) return -1;
    for (i = 2; i <= n; i++) {
        if (composite[i]) continue;
        count++;
        for (j = (int32_t)((int64_t)i * i <= n ? i * i : n + 1); j <= n; j += i) composite[j] = 1;
    }
    free(composite);
    return count;
}
```

Declare it in the BASIC program. `Alias` gives its C name, and a `Long` is a C `int32_t`:

<!-- fragment -->
```basic
Declare Function CountPrimesC Lib "C" Alias "count_primes" (ByVal n As Long) As Long
```

and make a project that names the C file with `CSource=`:

```ini
Name=Sieve
Startup=Sub Main
Module=sieve.bas
CSource=primes.c
```

Now `CountPrimesC(1000000)` gives the same 78498, several times faster. Build the program
natively and the C file is compiled into it:

```sh
1> boing build Sieve.bbp -o Sieve
1> Sieve --time
```

To run it in the interpreter, build an interpreter that includes the C code, once, and use it
instead of `boing`:

```sh
1> boing vm --project Sieve.bbp -o sieveboing
1> sieveboing run Sieve.bbp --time
```

(The standard `boing run Sieve.bbp` stops at the first call with error 453, "function
'CountPrimesC' is not linked into this program".)

## Step 3: an extension class

A C function is enough when the whole job can move into C. Often you want a building block
instead, used from BASIC: here a set of bits, one per number, much smaller than an array of
Booleans. That is an extension: a class written in C that the program uses like a built-in
object.

First describe it in `bits.bbx`:

```text
# bits.bbx - step 3: a BitSet class written in C
class BitSet
  method Resize(ByVal size As Long)
  method SetBit(ByVal i As Long)
  method TestBit(ByVal i As Long) As Boolean
  method SetEvery(ByVal start As Long, ByVal stepBy As Long)
  method NextClear(ByVal from As Long) As Long
  property Size As Long ReadOnly
  property Count As Long ReadOnly
```

Then write `bits.c`. The object is a `bb_obj` header followed by the class's own data, the size
and a pointer to the bits, and a table lists the members with a number for each:

```c
/* bits.c - step 3: a Boing BASIC extension, a BitSet class (one bit per number) */
#include "boing_ext.h"
#include <stdlib.h>

typedef struct bitset { bb_obj hdr; long size; unsigned char *bits; } bitset;

enum { M_RESIZE, M_SETBIT, M_TESTBIT, M_SETEVERY, M_NEXTCLEAR, P_SIZE, P_COUNT };
static const bb_member bitset_members[] = {
    {"Resize", M_RESIZE, BB_INV_METHOD}, {"SetBit", M_SETBIT, BB_INV_METHOD},
    {"TestBit", M_TESTBIT, BB_INV_METHOD}, {"SetEvery", M_SETEVERY, BB_INV_METHOD},
    {"NextClear", M_NEXTCLEAR, BB_INV_METHOD},
    {"Size", P_SIZE, BB_INV_GET}, {"Count", P_COUNT, BB_INV_GET},
};
```

`b_invoke` does the work for every member, switching on that number. A bad index raises
error 9, as an array would:

```c
/* an index the program gave us: error 9 (subscript out of range) if it is outside the set */
static long index_of(bitset *b, const bb_value *v)
{
    long i = bb_arg_long(v, 0);
    if (i < 0 || i >= b->size) bb_raise(9, NULL);
    return i;
}

static void b_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    bitset *b = (bitset *)self;
    long i, n, step;
    (void)kind; (void)argc;
    switch (id) {
    case M_RESIZE:
        n = bb_arg_long(argv, 0);
        if (n < 0) bb_raise(5, NULL);                     /* invalid procedure call */
        free(b->bits);
        b->bits = calloc((size_t)(n + 7) / 8 + 1, 1);
        if (!b->bits) { b->size = 0; bb_raise(7, NULL); }  /* out of memory */
        b->size = n;
        return;
    case M_SETBIT: i = index_of(b, &argv[0]); b->bits[i >> 3] |= (unsigned char)(1 << (i & 7)); return;
    case M_TESTBIT: i = index_of(b, &argv[0]); *ret = bb_ret_bool(b->bits[i >> 3] & (1 << (i & 7))); return;
    case M_SETEVERY:                                         /* start, start+step, ... */
        step = bb_arg_long(argv, 1);
        if (step < 1) bb_raise(5, NULL);
        for (i = bb_arg_long(argv, 0); i >= 0 && i < b->size; i += step)
            b->bits[i >> 3] |= (unsigned char)(1 << (i & 7));
        return;
    case M_NEXTCLEAR:                                        /* the first clear bit >= from, or -1 */
        for (i = bb_arg_long(argv, 0); i >= 0 && i < b->size; i++)
            if (!(b->bits[i >> 3] & (1 << (i & 7)))) { *ret = bb_ret_long(i); return; }
        *ret = bb_ret_long(-1);
        return;
    case P_SIZE: *ret = bb_ret_long(b->size); return;
    case P_COUNT:
        for (n = 0, i = 0; i < b->size; i++) n += (b->bits[i >> 3] >> (i & 7)) & 1;
        *ret = bb_ret_long(n);
        return;
    }
    bb_raise(438, NULL);
}
```

Finally the clean-up when the program lets go of a BitSet, the class itself (`BB_CLASS`), a
function that makes a new one, and the registration:

```c
static void b_terminate(bb_obj *self) { free(((bitset *)self)->bits); }

BB_CLASS(bitset_class, "BitSet", bitset, bitset_members, b_invoke, b_terminate);

static bb_obj *new_bitset(void) { return bb_obj_new(&bitset_class); }

BB_EXTENSION(bits)
{
    bb_register_class("BitSet", &bitset_class, new_bitset);
}
```

Add the extension to the project with `Extension=bits` (that means `bits.c` and `bits.bbx`).
The sieve with a BitSet:

<!-- project: examples/book/ex09-extending/Sieve.bbp -->
```basic
Function CountPrimesBits(ByVal n As Long) As Long
    ' one call per number: correct, but slower than plain BASIC (a call costs more than an array read)
    Dim composite As BitSet, i As Long, count As Long
    Set composite = New BitSet
    composite.Resize n + 1
    For i = 2 To n
        If Not composite.TestBit(i) Then
            count = count + 1
            If i <= n \ i Then composite.SetEvery i * i, i     ' the inner loop runs in C
        End If
    Next
    CountPrimesBits = count
End Function
```

Time it, and you'll find it is *slower* than the plain BASIC version. The crossing out runs in
C (`SetEvery`), but the outer loop calls `TestBit` a million times, and each call from BASIC
into an object costs more than reading an element of a BASIC array.

The cure is to make each call do more. `NextClear` searches for the next number that isn't
crossed out, in C, so the program makes one call per prime (78498) instead of one per number:

<!-- project: examples/book/ex09-extending/Sieve.bbp -->
```basic
Function CountPrimesBits2(ByVal n As Long) As Long
    ' one call per prime: NextClear does the searching in C
    Dim composite As BitSet, i As Long, count As Long
    Set composite = New BitSet
    composite.Resize n + 1
    i = composite.NextClear(2)
    Do While i <> -1
        count = count + 1
        If i <= n \ i Then composite.SetEvery i * i, i
        i = composite.NextClear(i + 1)
    Loop
    CountPrimesBits2 = count
End Function
```

## The complete program

`Sieve.bbp` lists all three parts:

```ini
Name=Sieve
Startup=Sub Main
Module=sieve.bas
CSource=primes.c
Extension=bits
```

and `Sub Main` runs the four versions:

<!-- project: examples/book/ex09-extending/Sieve.bbp -->
```basic
Sub Main()
    Dim n As Long, t As Double
    n = 1000000
    t = TimerMs()
    Print "BASIC:     "; CountPrimesBasic(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
    t = TimerMs()
    Print "C:         "; CountPrimesC(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
    t = TimerMs()
    Print "BitSet:    "; CountPrimesBits(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
    t = TimerMs()
    Print "NextClear: "; CountPrimesBits2(n)
    If Command() = "--time" Then Print "  "; Format(TimerMs() - t, "0"); " ms"
End Sub
```

```text
BASIC:      78498
C:          78498
BitSet:     78498
NextClear:  78498
```

With `--time` it also prints how long each took. In a typical run the C function is the
fastest by far, NextClear comes close to it, plain BASIC is in the middle, and the BitSet with
one call per number is the slowest. The same holds natively and in the interpreter; the
interpreter's BASIC version is the one that gains most from C.

## Run it

```sh
1> boing build Sieve.bbp -o Sieve           ; a native program, C included
1> Sieve --time
1> boing vm --project Sieve.bbp -o sieveboing
1> sieveboing run Sieve.bbp --time          ; the interpreter with the C code linked in
```

In AmiForge, **Build** (F7) makes the native program. For **Run** (the interpreter), set
**Project > Settings > Boing BASIC command** to the `sieveboing` you built.

## Try this

1. Give the BitSet a `ClearBit` method and a `Toggle` method, add them to `bits.bbx`, and check
   that `boing check` catches a misspelt `ClearBti`.
2. Write `Function SumOfPrimes(ByVal n As Long) As Double` in C and call it with `Declare ...
   Lib "C"`. What is the sum of the primes below two million?
3. Turn `primes.c` into an extension function instead: add
   `function CountPrimesX(ByVal n As Long) As Long` to a `.bbx` and register it with
   `bb_register_function`. What changes in the BASIC program?
4. Write the BitSet in C++ with `std::vector<bool>` (see the C++ example in chapter 20).
5. Measure: how many calls per second does your computer make into an extension method? Time
   a million calls to `TestBit`.
