#!/usr/bin/env python3
"""Glimmerfield's sound on the AmigaOS 4 guest: is sound produced, and what does it cost?

    BB_GUEST=m1b examples/glimmerfield/tools/guest_sound.py [FRAMES]

(m1 is the user's own guest: agents use m1b or local.)

Runs the native build (build/os4/Glimmerfield, made here with `boing build --target os4`)
from RAM:glimsnd/ with `--bench FRAMES` twice: without sound and with `--sound` (music and the
bot's effects at moderate volume, the effects heard only in play, so in the bench: music).
During the sound run the guest's audio output is recorded with QEMU's HMP `wavcapture` (on
the machine running QEMU, over ssh for a remote guest) and its level is reported. Holds the emulator lock
and banner (tools/os4guest.py), leaves nothing running and deletes RAM:glimsnd afterwards.
"""
import os, re, struct, subprocess, sys, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g

FRAMES = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
HMP_PORT = int(os.environ.get("OS4_HMP_PORT", "2448" if g.GUEST == "m1b" else "2348"))   # m1b's QEMU monitor: m1:2448
CAP = "/tmp/bb_glim_sound.wav"


def hmp(cmd):
    """one HMP command on the QEMU monitor (on the guest's host)"""
    py = ("import socket,time;s=socket.create_connection(('127.0.0.1',%d),5);time.sleep(0.3);s.recv(65536);"
          "s.sendall(b'%s\\n');time.sleep(1);print(s.recv(65536).decode('latin-1'));s.close()" % (HMP_PORT, cmd))
    if g.SSH:
        return g._ssh("python3 -c \"%s\"" % py).stdout
    return subprocess.run(["python3", "-c", py], capture_output=True, text=True).stdout


def level(path):
    if g.SSH:
        data = subprocess.run(["ssh", g.SSH, "cat " + path], capture_output=True).stdout
    else:
        data = open(path, "rb").read()
    if len(data) <= 44:
        return 0, 0.0, 0
    s = struct.unpack("<%dh" % ((len(data) - 44) // 2), data[44:44 + (len(data) - 44) // 2 * 2])
    rms = (sum(x * x for x in s) / len(s)) ** 0.5
    return len(s) / 2 / 44100.0, rms, max(abs(x) for x in s)


def main():
    exe = os.path.join(ROOT, "build/os4/Glimmerfield")
    subprocess.check_call([os.path.join(ROOT, "build/boing"), "build",
                           os.path.join(ROOT, "examples/glimmerfield/Glimmerfield.bbp"), "--target", "os4", "-o", exe])
    m = g.MCP(g.URL)
    dos = lambda c: str(m.tool("amiga_dos_command", command=c))
    res = {}
    with g.testing("Boing BASIC: sound tests"):
        # tests-os4/audio: the Mac's PCM hashes on OS4, then AHI output (VM)
        dos("makedir RAM:bbt RAM:bbt/tests-os4 RAM:bbt/tests-os4/audio QUIET")
        print(g.push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbt/boing"))
        for f in ("audio.bas", "fx.mod"):
            print(g.push(m, os.path.join(ROOT, "tests-os4/audio", f), "RAM:bbt/tests-os4/audio/" + f))
        out = g.run_bg(m, "RAM:bbt/boing run RAM:bbt/tests-os4/audio/audio.bas", "RAM:bbt/audio.out")
        print("== tests-os4/audio (vm)\n" + out)
        res["test"] = out
        dos("makedir RAM:glimsnd QUIET")
        print(g.push(m, exe, "RAM:glimsnd/Glimmerfield"))
        print(g.push(m, os.path.join(ROOT, "examples/glimmerfield/glimmer.mod"), "RAM:glimsnd/glimmer.mod"))
        for name, args in (("silent", ""), ("sound", " --sound")):
            dos("delete RAM:glimsnd/out.txt QUIET")
            if name == "sound":
                print(hmp("wavcapture %s snd0" % CAP).strip().splitlines()[-1:])
            dos("run >NIL: RAM:glimsnd/Glimmerfield --bench %d%s >RAM:glimsnd/out.txt" % (FRAMES, args))
            t0, out = time.time(), ""
            while time.time() - t0 < 300:
                time.sleep(3)
                out = dos("type RAM:glimsnd/out.txt")
                if "blit:" in out and (name == "silent" or "sound:" in out):
                    break
            if name == "sound":
                info = hmp("info capture")
                mm = re.search(r"\[(\d+)\]", info)
                hmp("stopcapture %s" % (mm.group(1) if mm else "0"))
            res[name] = out
            print("== %s\n%s" % (name, out.strip()))
            time.sleep(2)
        dos("delete RAM:glimsnd ALL QUIET")
    secs, rms, peak = level(CAP)
    print("capture: %.1f s, rms %.0f, peak %d -> %s" % (secs, rms, peak, "SOUND" if rms > 50 else "SILENT"))
    f = lambda o: float(re.search(r"= ([\d.]+) ms/frame", o).group(1)) if re.search(r"= ([\d.]+) ms/frame", o) else None
    a, b = f(res.get("silent", "")), f(res.get("sound", ""))
    if a and b:
        print("frame time: %.3f ms without sound, %.3f ms with: +%.3f ms (%.1f %%)" % (a, b, b - a, (b - a) * 100 / a))


if __name__ == "__main__":
    main()
