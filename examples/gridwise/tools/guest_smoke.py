#!/usr/bin/env python3
"""guest_smoke.py - run an office app (Gridwise, Penwright) on an AmigaOS 4 guest with a
command script, take a screenshot at each "PAUSE n tag" of the script, and check the log.

    BB_GUEST=m1 examples/gridwise/tools/guest_smoke.py BINARY SCRIPT [--push LOCAL AMIGA ...]
        [--expect TEXT ...] [--shots PREFIX] [--args "extra args"]

The binary and script go to DH1:office/ on the guest; the app runs as
`BINARY [args] --script DH1:office/SCRIPT --log DH1:office/smoke.log`. The app writes
"paused <tag>" as the log's last line while it waits in a PAUSE: this tool then saves a
screendump (QEMU HMP, over ssh for a remote guest) as PREFIX_<tag>.png. At the end the
log must end with "ok", contain every --expect text and no "[rc 10]".
`guest_smoke.py --shot OUT.png` only takes a screenshot.
Holds the guest's lock and the "CLAUDE IS TESTING" banner (tools/os4guest.py).
"""
import os, socket, subprocess, sys, tempfile, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g  # noqa: E402

HMP_PORT = int(os.environ.get("OS4_HMP_PORT", "2348"))


def screendump(local_png):
    """Whole-screen PPM via QEMU's monitor, converted to PNG."""
    remote = "/tmp/bb_office_shot.ppm"
    if g.SSH:
        py = ("import socket,time;s=socket.create_connection(('127.0.0.1',%d),10);time.sleep(0.5);s.recv(65536);"
              "s.sendall(b'screendump %s\\n');time.sleep(2);s.recv(65536);s.close()" % (HMP_PORT, remote))
        subprocess.run(["ssh", g.SSH, "python3", "-c", '"%s"' % py], check=True, timeout=60)
        tmp = tempfile.mktemp(suffix=".ppm")
        subprocess.run(["scp", "-q", "%s:%s" % (g.SSH, remote), tmp], check=True, timeout=60)
    else:
        tmp = tempfile.mktemp(suffix=".ppm")
        s = socket.create_connection(("127.0.0.1", HMP_PORT), timeout=10)
        time.sleep(0.5); s.recv(65536)
        s.sendall(("screendump %s\n" % tmp).encode()); time.sleep(2); s.recv(65536); s.close()
    try:
        from PIL import Image
        Image.open(tmp).save(local_png)
    except ImportError:
        os.rename(tmp, local_png.replace(".png", ".ppm"))
        return
    os.unlink(tmp)
    print("screenshot", local_png)


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        sys.exit(__doc__)
    binary, script = a[0], a[1]
    pushes, expects, shots, extra = [], [], os.path.join(tempfile.gettempdir(), "office"), ""
    i = 2
    while i < len(a):
        if a[i] == "--push":
            pushes.append((a[i + 1], a[i + 2])); i += 3
        elif a[i] == "--expect":
            expects.append(a[i + 1]); i += 2
        elif a[i] == "--shots":
            shots = a[i + 1]; i += 2
        elif a[i] == "--args":
            extra = a[i + 1]; i += 2
        else:
            sys.exit("unknown option " + a[i])
    name = os.path.basename(binary)
    m = g.MCP(g.URL)
    dos = lambda c: str(m.tool("amiga_dos_command", command=c))
    ok = False
    with g.testing("Boing BASIC: %s smoke test" % name):
        print(g.push(m, binary, "DH1:office/" + name))
        print(g.push(m, script, "DH1:office/" + os.path.basename(script)))
        for loc, dest in pushes:
            print(g.push(m, loc, dest))
        dos("delete DH1:office/smoke.log QUIET")
        dos("run >NIL: DH1:office/%s %s --script DH1:office/%s --log DH1:office/smoke.log"
            % (name, extra, os.path.basename(script)))
        seen, t0, log = set(), time.time(), ""
        while time.time() - t0 < float(os.environ.get("BB_TEST_TIMEOUT", "240")):
            time.sleep(1.5)
            log = dos("type DH1:office/smoke.log")
            lines = [l for l in log.splitlines() if l.strip()]
            last = lines[-1].strip() if lines else ""
            if last.startswith("paused "):
                tag = last[7:].strip() or "shot%d" % len(seen)
                if tag not in seen:
                    seen.add(tag)
                    screendump("%s_%s.png" % (shots, tag))
            elif last == "ok":
                break
        print(log)
        ok = log.rstrip().endswith("ok") and "[rc 10]" not in log and all(e in log for e in expects)
        missing = [e for e in expects if e not in log]
        if missing:
            print("missing:", missing)
        # leave nothing behind: the script ends with QUIT; check the window is gone
        time.sleep(2)
        st = dos("status")
        if name.lower() in st.lower():
            print("WARNING: %s still running:\n%s" % (name, st))
            ok = False
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--shot":
        screendump(sys.argv[2])
    else:
        main()
