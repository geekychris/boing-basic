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
--keys TAG "A-B DOWN 3 0 RETURN" types keys while the app waits in "PAUSE n TAG", and only
while the app's window is the active one (the app writes "active"/"inactive" to
DH1:office/state, --state): A-x = Amiga+x, S-x = Shift+x, a..z (A..Z typed with Shift), digits, SPACE, RETURN,
TAB, BS, DEL, ESC, UP, DOWN, LEFT, RIGHT.
--rexx TAG FILE.rexx runs that ARexx script (pushed to DH1:office/) with rx while the app
waits in "PAUSE n TAG"; its output counts for --expect (scripts drive the app's port).
`guest_smoke.py --shot OUT.png` only takes a screenshot.
Holds the guest's lock and the "CLAUDE IS TESTING" banner (tools/os4guest.py).
"""
import os, socket, subprocess, sys, tempfile, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g  # noqa: E402

HMP_PORT = int(os.environ.get("OS4_HMP_PORT", "2348"))
RAW = {"SPACE": 0x40, "BS": 0x41, "TAB": 0x42, "RETURN": 0x44, "ESC": 0x45, "DEL": 0x46,
       "UP": 0x4C, "DOWN": 0x4D, "RIGHT": 0x4E, "LEFT": 0x4F, ",": 0x38, ".": 0x39, "=": 0x0C, "-": 0x0B}
for i, ch in enumerate("1234567890"):
    RAW[ch] = 0x01 + i
for row, base in (("QWERTYUIOP", 0x10), ("ASDFGHJKL", 0x20), ("ZXCVBNM", 0x31)):
    for i, ch in enumerate(row):
        RAW[ch] = base + i
LSHIFT, RAMIGA = 0x60, 0x67


def send_keys(m, seq):
    """type a key sequence (see --keys)"""
    def key(code, d):
        m.tool("amiga_input_key", rawkey="%02x" % code, direction=d)
        time.sleep(0.08)
    for tok in seq.split():
        quals = []
        while len(tok) > 2 and tok[1] == "-" and tok[0] in "AS":
            quals.append(RAMIGA if tok[0] == "A" else LSHIFT)
            tok = tok[2:]
        code = RAW.get(tok.upper())
        if code is None:
            raise SystemExit("unknown key " + tok)
        if tok.isalpha() and len(tok) == 1 and tok.isupper() and not quals:
            quals.append(LSHIFT)          # a capital letter
        for q in quals:
            key(q, "down")
        key(code, "down")
        key(code, "up")
        for q in reversed(quals):
            key(q, "up")
        time.sleep(0.25)


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
    pushes, expects, shots, extra, keys, rexx = [], [], os.path.join(tempfile.gettempdir(), "office"), "", {}, {}
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
        elif a[i] == "--rexx":
            rexx[a[i + 1]] = a[i + 2]; i += 3
        elif a[i] == "--keys":
            keys[a[i + 1]] = a[i + 2]; i += 3
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
        for f in rexx.values():
            print(g.push(m, f, "DH1:office/" + os.path.basename(f)))
        dos("delete DH1:office/smoke.log DH1:office/state QUIET")
        dos("run >NIL: DH1:office/%s %s --script DH1:office/%s --log DH1:office/smoke.log --state DH1:office/state"
            % (name, extra, os.path.basename(script)))
        seen, t0, log, ok_keys, rexx_out = set(), time.time(), "", True, []
        while time.time() - t0 < float(os.environ.get("BB_TEST_TIMEOUT", "240")):
            time.sleep(1.5)
            log = dos("type DH1:office/smoke.log")
            lines = [l for l in log.splitlines() if l.strip()]
            last = lines[-1].strip() if lines else ""
            if last.startswith("paused "):
                tag = last[7:].strip() or "shot%d" % len(seen)
                if tag not in seen:
                    seen.add(tag)
                    if tag in keys:
                        st = dos("type DH1:office/state").strip()
                        if st.splitlines()[-1:] != ["active"]:
                            print("our window is not the active one (%r): not sending keys" % st)
                            ok_keys = False
                        else:
                            send_keys(m, keys[tag])
                            time.sleep(1)
                    if tag in rexx:
                        out = dos("rx DH1:office/" + os.path.basename(rexx[tag]))
                        print("rexx:", out)
                        rexx_out.append(out)
                    screendump("%s_%s.png" % (shots, tag))
            elif last == "ok":
                break
        print(log)
        everything = log + "\n".join(rexx_out)
        ok = ok_keys and log.rstrip().endswith("ok") and "[rc 10]" not in log and all(e in everything for e in expects)
        missing = [e for e in expects if e not in everything]
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
