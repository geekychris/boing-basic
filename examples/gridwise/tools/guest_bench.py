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
    m = g.MCP(g.URL)
    exes = {}
    for n in names:
        src = BENCHES[n][0]
        exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(src))[0] + ".exe")
        if "native" in modes:
            subprocess.check_call([os.path.join(ROOT, "tools/boing-build-os4.sh"), os.path.join(ROOT, src), "-o", exe],
                                  stdout=subprocess.DEVNULL)
        exes[n] = exe
    with g.testing("Boing BASIC: office benchmarks"):
        g.push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbt/boing")
        g.push(m, os.path.join(ROOT, "examples/penwright/penwright.dict"), "RAM:bbt/penwright.dict")
        for n in names:
            src, args, done = BENCHES[n]
            d = os.path.dirname(os.path.join(ROOT, src))
            files = [os.path.join(d, f) for f in os.listdir(d) if f.endswith((".bas", ".bbp"))]
            for line in open(os.path.join(ROOT, src)):
                mm = re.match(r"\s*Module\s*=\s*(\S+)", line)
                if mm:
                    files.append(os.path.normpath(os.path.join(d, mm.group(1))))
            for f in sorted(set(files)):
                g.push(m, f, "RAM:bbt/" + os.path.relpath(f, ROOT))
            amiga = "RAM:bbt/" + src
            for mode in modes:
                if mode == "native":
                    g.push(m, exes[n], "RAM:bbt/%s.exe" % n)
                    cmd = "RAM:bbt/%s.exe %s" % (n, args)
                else:
                    cmd = "RAM:bbt/boing run %s%s %s" % ("--jit " if mode == "jit" else "", amiga, args)
                t = time.time()
                out = run(m, cmd, "RAM:bbt/%s_%s.out" % (n, mode), done)
                print("== %s %s (%.0f s wall)\n%s" % (n, mode, time.time() - t, out.strip()))
                sys.stdout.flush()
        m.tool("amiga_dos_command", command="delete RAM:bbt/sheet.exe RAM:bbt/pw.exe RAM:bbt/#?.out#? QUIET")


main()
