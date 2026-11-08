#!/usr/bin/env python3
"""bench.py - Boing BASIC benchmark suite (make bench).

Runs every bench/*.bas (and bench/<dir>/<dir>.bbp) in the VM (boing run) and as a native
build (boing build, host cc -O2), plus the hand-written C twin in bench/c/ when there is one.
Checks that VM and native print the same thing, takes the best of --runs wall-clock times
and prints a Markdown table: VM s, native s, VM/native, C s, native/C.

    tools/bench.py [--scale N] [--runs R] [--only name,name] [--boing build/boing] [--md out.md]
"""
import argparse, os, subprocess, sys, time, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def timed(cmd, cwd, runs):
    best, out = None, None
    for _ in range(runs):
        t0 = time.perf_counter()
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        dt = time.perf_counter() - t0
        if p.returncode != 0:
            return None, (p.stdout + p.stderr)
        out = p.stdout
        best = dt if best is None or dt < best else best
    return best, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", default="1")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--only", default="")
    ap.add_argument("--boing", default=os.path.join(ROOT, "build", "boing"))
    ap.add_argument("--cc", default=os.environ.get("CC", "cc"))
    ap.add_argument("--md", default="")
    a = ap.parse_args()
    bdir = os.path.join(ROOT, "bench")
    items = []
    for f in sorted(os.listdir(bdir)):
        p = os.path.join(bdir, f)
        if f.endswith(".bas"):
            items.append((f[:-4], bdir, f, [a.scale]))
        elif os.path.isdir(p) and os.path.exists(os.path.join(p, f + ".bbp")):
            items.append((f, p, f + ".bbp", [a.scale]))
    # real-world: bb-game's Glimmerfield (game logic; with --draw also the BASIC renderer)
    gdir = os.path.join(ROOT, "examples", "glimmerfield")
    if os.path.exists(os.path.join(gdir, "Bench.bbp")):
        n = int(float(a.scale) * 20000)
        items.append(("glimmerfield", gdir, "Bench.bbp", ["--bench", str(n), "--quiet"]))
        items.append(("glimmerfield_draw", gdir, "Bench.bbp", ["--bench", str(n // 80), "--draw", "--quiet"]))
    if a.only:
        want = set(a.only.split(","))
        items = [i for i in items if i[0] in want]
    tmp = tempfile.mkdtemp(prefix="bbbench")
    rows = []
    for name, cwd, src, args in items:
        exe = os.path.join(tmp, name)
        b = subprocess.run([a.boing, "build", src, "-o", exe], cwd=cwd, capture_output=True, text=True)
        vm_t, vm_out = timed([a.boing, "run", "--no-jit", src] + args, cwd, a.runs)
        jit_t, jit_out = timed([a.boing, "run", "--jit", src] + args, cwd, a.runs)
        nat_t, nat_out = (None, b.stderr) if b.returncode else timed([exe] + args, cwd, a.runs)
        c_t = None
        csrc = os.path.join(bdir, "c", name + ".c")
        if os.path.exists(csrc):
            cexe = os.path.join(tmp, name + "_c")
            if subprocess.run([a.cc, "-O2", "-o", cexe, csrc, "-lm"], capture_output=True).returncode == 0:
                c_t, _ = timed([cexe, a.scale], cwd, a.runs)
        ok = vm_t is not None and nat_t is not None and vm_out == nat_out and jit_out == vm_out
        if not ok:
            print(f"{name}: VM and native differ or failed", file=sys.stderr)
            print("VM:", (vm_out or "")[:300], "\nnative:", (nat_out or "")[:300], file=sys.stderr)
        rows.append((name, vm_t, jit_t, nat_t, c_t, ok))
        print(f"  {name}: vm {vm_t} jit {jit_t} native {nat_t} c {c_t}", file=sys.stderr)
    shutil.rmtree(tmp, ignore_errors=True)

    def f(x):
        return "-" if x is None else f"{x:.3f}"

    def ratio(x, y):
        return "-" if x is None or y is None or y == 0 else f"{x / y:.1f}x"

    lines = ["| benchmark | VM (s) | VM+JIT (s) | native (s) | VM/native | JIT/native | C (s) | native/C | same output |",
             "|---|---:|---:|---:|---:|---:|---:|---:|:---:|"]
    for name, v, j, n, c, ok in rows:
        lines.append(f"| {name} | {f(v)} | {f(j)} | {f(n)} | {ratio(v, n)} | {ratio(j, n)} | {f(c)} | {ratio(n, c)} | {'yes' if ok else 'NO'} |")
    table = "\n".join(lines)
    print(table)
    if a.md:
        with open(a.md, "w") as fh:
            fh.write(table + "\n")
    return 0 if all(r[5] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
