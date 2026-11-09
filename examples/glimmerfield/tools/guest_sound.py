#!/usr/bin/env python3
"""Glimmerfield's sound on the AmigaOS 4 guest: is sound produced, and what does it cost?

    BB_GUEST=m1b|m1c examples/glimmerfield/tools/guest_sound.py [FRAMES]

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

VM = "--vm" in sys.argv          # Glimmerfield under `boing run` (the VM) instead of the native build
_args = [a for a in sys.argv[1:] if a != "--vm"]
FRAMES = int(_args[0]) if _args else (600 if VM else 1500)
CAP = "/tmp/bb_glim_sound.wav"


def hmp(cmd):
    """one command on the selected guest's QEMU monitor (os4guest.hmp: its own port, refuses m1)"""
    return g.hmp(cmd)


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
    if VM:
        return main_vm()
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


def main_vm():
    """--vm: the audio test and Glimmerfield under build/os4/boing, both started from another
    current directory (App.Path must be the program's own drawer), with the capture."""
    gdir = os.path.join(ROOT, "examples/glimmerfield")
    files = [f for f in sorted(os.listdir(gdir)) if os.path.splitext(f)[1].lower() in (".bas", ".bbp", ".afg", ".cls", ".mod")]
    m = g.MCP(g.URL)
    dos = lambda c: str(m.tool("amiga_dos_command", command=c))
    with g.testing("Boing BASIC: Glimmerfield VM sound"):
        dos("makedir RAM:bbt RAM:bbt/tests-os4 RAM:bbt/tests-os4/audio RAM:glimvm QUIET")
        print(g.push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbt/boing"))
        for f in ("audio.bas", "fx.mod"):
            print(g.push(m, os.path.join(ROOT, "tests-os4/audio", f), "RAM:bbt/tests-os4/audio/" + f))
        for f in files:
            g.push(m, os.path.join(gdir, f), "RAM:glimvm/" + f)
        print("current directory of the commands:", dos("cd").strip())
        out = g.run_bg(m, "RAM:bbt/boing run RAM:bbt/tests-os4/audio/audio.bas", "RAM:bbt/audio.out")
        print("== tests-os4/audio (vm)\n" + out.strip())
        dos("delete RAM:glimvm/out.txt QUIET")
        print(hmp("wavcapture %s snd0" % CAP).strip().splitlines()[-1:])
        dos("run >NIL: RAM:bbt/boing run RAM:glimvm/Glimmerfield.bbp --bench %d --sound >RAM:glimvm/out.txt" % FRAMES)
        t0, out = time.time(), ""
        while time.time() - t0 < 200:
            time.sleep(3)
            out = dos("type RAM:glimvm/out.txt")
            if "sound:" in out or "error" in out.lower():
                break
        info = hmp("info capture")
        mm = re.search(r"\[(\d+)\]", info)
        hmp("stopcapture %s" % (mm.group(1) if mm else "0"))
        print("== Glimmerfield (vm) --bench %d --sound\n%s" % (FRAMES, out.strip()))
        time.sleep(2)
        print("reapers:", g.reapers(m))
        dos("delete RAM:glimvm ALL QUIET")
    secs, rms, peak = level(CAP)
    print("capture: %.1f s, rms %.0f, peak %d -> %s" % (secs, rms, peak, "SOUND" if rms > 50 else "SILENT"))
    if g.SSH:
        g._ssh("rm -f " + CAP)


if __name__ == "__main__":
    main()
