#!/usr/bin/env python3
"""guest_bench.py - the office apps' benchmarks on an AmigaOS 4 guest: Gridwise's
SheetBench (1000 x 26 sheet: entering, recalculation, edits, drawing) and Penwright's
PwBench (300 paragraphs: layout, drawing, typing, spelling, export), each in the VM, the
VM with the JIT (--jit) and as a native build.

    BB_GUEST=m1 examples/gridwise/tools/guest_bench.py [sheet|pw|all] [vm|jit|native|all]

Prints each run's timing lines. Takes the guest's lock and banner (tools/os4guest.py).
"""
import os, re, subprocess, sys, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g  # noqa: E402

BENCHES = {
    "sheet": ("examples/gridwise/bench/SheetBench.bbp", "", "Z1="),
    "pw": ("examples/penwright/bench/PwBench.bbp", "300 RAM:bbt/penwright.dict", "RTF export"),
}


def run(m, cmd, outf, done, limit=900):
    dos = lambda c: str(m.tool("amiga_dos_command", command=c))
    dos("delete %s QUIET" % outf)
    dos("run >NIL: %s >%s *>%s.err" % (cmd, outf, outf))
    t0 = time.time()
    while time.time() - t0 < limit:
        time.sleep(3)
        out = dos("type %s" % outf)
        if done in out:
            return out
        err = dos("type %s.err" % outf)
        if "error" in err:
            return out + "\n" + err
    return out + "\n(timed out)"


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    modes = sys.argv[2] if len(sys.argv) > 2 else "all"
    names = list(BENCHES) if which == "all" else [which]
    modes = ["vm", "jit", "native"] if modes == "all" else [modes]
    if g.GUEST == "m1" and os.environ.get("BB_ALLOW_M1") != "1":
        sys.exit("guest_bench: m1 is the user's guest; use BB_GUEST=m1b, m1c or local")
    os.environ.setdefault("BB_SESSION_TIMEOUT", "300")
    m = g.MCP(g.URL)
    exes = {}
    for n in names:
        src = BENCHES[n][0]
        exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(src))[0] + ".exe")
        if "native" in modes:
            subprocess.check_call([os.path.join(ROOT, "tools/boing-build-os4.sh"), os.path.join(ROOT, src), "-o", exe],
                                  stdout=subprocess.DEVNULL)
        exes[n] = exe
    for n in names:
        src, args, done = BENCHES[n]
        d = os.path.dirname(os.path.join(ROOT, src))
        files = [os.path.join(d, f) for f in os.listdir(d) if f.endswith((".bas", ".bbp"))]
        for line in open(os.path.join(ROOT, src)):
            mm = re.match(r"\s*Module\s*=\s*(\S+)", line)
            if mm:
                files.append(os.path.normpath(os.path.join(d, mm.group(1))))
        amiga = "RAM:bbt/" + src
        for mode in modes:
            # one lock session per run (each well under the 5-minute session limit)
            with g.testing("Boing BASIC: %s benchmark (%s)" % (n, mode)):
                g.push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbt/boing")
                if n == "pw":
                    g.push(m, os.path.join(ROOT, "examples/penwright/penwright.dict"), "RAM:bbt/penwright.dict")
                for f in sorted(set(files)):
                    g.push(m, f, "RAM:bbt/" + os.path.relpath(f, ROOT))
                if mode == "native":
                    g.push(m, exes[n], "RAM:bbt/%s.exe" % n)
                    cmd = "RAM:bbt/%s.exe %s" % (n, args)
                else:
                    cmd = "RAM:bbt/boing run %s%s %s" % ("--jit " if mode == "jit" else "", amiga, args)
                t = time.time()
                out = run(m, cmd, "RAM:bbt/%s_%s.out" % (n, mode), done, limit=240)
                print("== %s %s (%.0f s wall)\n%s" % (n, mode, time.time() - t, out.strip()))
                sys.stdout.flush()
    with g.testing("Boing BASIC: benchmark clean-up"):
        m.tool("amiga_dos_command", command="delete RAM:bbt/sheet.exe RAM:bbt/pw.exe RAM:bbt/#?.out#? QUIET")


main()
