#!/bin/sh
# os4-form-test.sh [vm|native|both] - the BASIC forms test (tests-os4/formbas) on the QEMU
# guest: `boing run formbas.bbp` (vm) and/or the native build from `boing build --target os4`.
# The program prints "CLICK x y"; this script clicks there with tools/os4/ptr (only when the
# test's window is on the front screen) and expects ok_Click to run. Holds the emulator lock.
root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-both}
cd "$root" || exit 20
[ -f build/os4/boing ] && [ -f build/os4/ptr ] || tools/build-os4.sh >/dev/null || exit 20
exec python3 - "$mode" <<'PY'
import os, re, sys, time, subprocess
sys.path.insert(0, "tools")
import os4guest as g
mode = sys.argv[1]
m = g.MCP(g.URL)
T = "tests-os4/formbas/"
TITLE = "Boing BASIC form test - running"
def run(cmd, label):
    out_f = "RAM:bbform/%s.out" % label
    m.tool("amiga_dos_command", command="delete %s QUIET" % out_f)
    m.tool("amiga_dos_command", command="run >NIL: %s >%s" % (cmd, out_f))
    clicked, t0, out = False, time.time(), ""
    while time.time() - t0 < 90:
        time.sleep(2)
        out = m.tool("amiga_dos_command", command="type %s" % out_f)
        c = re.search(r"CLICK\s+(-?\d+)\s+(-?\d+)", out)
        if c and not clicked:
            clicked = True
            r = m.tool("amiga_dos_command", command="RAM:bbform/ptr %s %s click \"%s\"" % (c.group(1), c.group(2), TITLE))
        if re.search(r"^(PASS|FAIL)", out, re.M):
            break
    print("== %s\n%s" % (label, out))
    return bool(re.search(r"^PASS", out, re.M))
ok = True
with g.testing("Boing BASIC form test"):
    m.tool("amiga_dos_command", command="makedir RAM:bbform")
    files = [("build/os4/ptr", "RAM:bbform/ptr")]
    for f in ("formbas.bbp", "formbas.afg", "formbas.bas"):
        files.append((T + f, "RAM:bbform/" + f))
    if mode in ("vm", "both"):
        files.append(("build/os4/boing", "RAM:bbform/boing"))
    if mode in ("native", "both"):
        subprocess.check_call(["build/boing", "build", T + "formbas.bbp", "--target", "os4", "-o", "build/os4/formbas"])
        files.append(("build/os4/formbas", "RAM:bbform/formbas"))
    for a, b in files:
        g.push(m, a, b)
    if mode in ("vm", "both"):
        ok &= run("RAM:bbform/boing run RAM:bbform/formbas.bbp", "vm")
    if mode in ("native", "both"):
        ok &= run("RAM:bbform/formbas", "native")
print("os4 form test:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
