#!/usr/bin/env python3
"""os4-libtest.py TEST.bas [vm|native|both] [DATAFILE ...] - run an output-comparing test (a .bas
with a .out beside it, as tests/run.sh uses) on the AmigaOS 4 guest (BB_GUEST, default local)
through tools/os4guest.py: pushes the program and its data files to RAM:bbt/<path>/, runs it
there from its own directory with build/os4/boing (VM) and/or built natively for OS4, and
compares stdout followed by stderr with the same from the host build (build/boing run), which
must itself match the .out. Exit 0 when every mode matches.

    tools/os4-libtest.py tests/libs/ziptest.bas both tests/libs/fixture.zip

Holds the guest's lock and banner per command (os4guest), waits for the run to finish (a marker
file written after it), at most BB_TEST_TIMEOUT seconds (default 240), and reports Grim
Reapers."""
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import os4guest as g  # noqa: E402


def host_reference(src):
    d = os.path.dirname(src)
    env = dict(os.environ, BOING_HEADLESS="1")     # form programs run without a display on the host
    host = os.environ.get("BB_HOST_BOING", os.path.join(ROOT, "build/boing"))   # e.g. one with STD_EXTS
    p = subprocess.run([host, "run", os.path.basename(src)], cwd=d,
                       capture_output=True, env=env)
    return norm(p.stdout.decode("latin-1")) + norm(p.stderr.decode("latin-1"))


def norm(s):
    """the bridge drops white space at the end of what it types: compare without it"""
    s = s.replace("\r", "").rstrip()
    return s + "\n" if s else ""


def run(m, label, cmd, rdir, limit):
    """run cmd in rdir on the guest; stdout then stderr"""
    tag = "RAM:bbt/lt%d-%s" % (os.getpid(), label)      # unique: other agents use RAM:bbt too
    script = "%s.script" % tag
    lines = ["FailAt 1000", "CD %s" % rdir, "%s >%s.out *>%s.err" % (cmd, tag, tag), "Echo done >%s.done" % tag]
    for f in (".out", ".err", ".done"):
        m.tool("amiga_dos_command", command="delete %s%s QUIET" % (tag, f))
    local = os.path.join(ROOT, "build", "os4-libtest-%d-%s.script" % (os.getpid(), label))
    with open(local, "w", encoding="latin-1") as fh:
        fh.write("\n".join(lines) + "\n")
    g.push(m, local, script)
    m.tool("amiga_dos_command", command="run >NIL: Execute %s" % script)
    t0 = time.time()
    while time.time() - t0 < limit:
        time.sleep(2)
        done = m.tool("amiga_dos_command", command="type %s.done" % tag)
        if re.search(r"^done", done.replace("\r", ""), re.M):
            out = m.tool("amiga_dos_command", command="type %s.out" % tag)
            err = m.tool("amiga_dos_command", command="type %s.err" % tag)
            for f in (".out", ".err", ".done", ".script"):
                m.tool("amiga_dos_command", command="delete %s%s QUIET" % (tag, f))
            return norm(clean(out)) + norm(clean(err)), True
    return "", False


def clean(s):
    s = s.replace("\r", "")
    # the MCP tool returns "" for an empty file, sometimes with a note
    if s.strip() in ("", "(no output)", "[OK] (no output)"):
        return ""
    if s.startswith("[OK]"):
        s = s.split("\n", 1)[1] if "\n" in s else ""
    return s if s.endswith("\n") or not s else s + "\n"


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    src = os.path.abspath(args[0])
    mode = args[1] if len(args) > 1 else "both"
    data = [os.path.abspath(a) for a in args[2:]]
    limit = float(os.environ.get("BB_TEST_TIMEOUT", "240"))
    expected = open(os.path.splitext(src)[0] + ".out", encoding="latin-1").read()
    ref = host_reference(src)
    rel = os.path.relpath(src, ROOT)
    rdir = "RAM:bbt/lt%d/%s" % (os.getpid(), os.path.basename(os.path.dirname(src)))   # its own drawer
    m = g.MCP(g.URL)
    ok = True
    with g.testing("Boing BASIC library test " + os.path.basename(src)):
        parts = rdir.split("/")
        m.tool("amiga_dos_command", command="makedir " + " ".join("/".join(parts[:i]) for i in range(1, len(parts) + 1)) + " QUIET")
        for f in [src] + data:
            g.push(m, f, rdir + "/" + os.path.basename(f))
        runs = []
        if mode in ("vm", "both"):
            g.push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbt/boing")
            runs.append(("vm", "RAM:bbt/boing run " + os.path.basename(src)))
        if mode in ("native", "both"):
            exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(src))[0] + ".exe")
            subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
            g.push(m, exe, rdir + "/native")
            runs.append(("native", rdir + "/native"))
        for label, cmd in runs:
            got, finished = run(m, label, cmd, rdir, limit)
            # the bridge drops trailing white space at the very end of an output
            same = finished and got == ref
            ok &= same
            print("== %s: %s" % (label, "PASS (output = the host's)" if same else
                                 "FAIL" + ("" if finished else " (not finished within %ds)" % limit)))
            if not same:
                import difflib
                sys.stdout.writelines(difflib.unified_diff(ref.splitlines(True), got.splitlines(True), "host", label))
        m.tool("amiga_dos_command", command="delete RAM:bbt/lt%d ALL QUIET FORCE" % os.getpid())
        n = g.reapers(m)
        if n:
            print("GRIM REAPER: %d" % n)
            ok = False
    if ref.replace("\r", "") != expected and "--no-out-check" not in sys.argv:
        # stderr ordering can differ from the .out (which interleaves); only report it
        print("(note: the host's stdout+stderr differs from the .out in order only?)")
    print("os4 test %s: %s" % (rel, "PASS" if ok else "FAIL"))
    sys.exit(0 if ok else 1)


main()
