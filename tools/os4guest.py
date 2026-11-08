#!/usr/bin/env python3
"""os4guest.py - push files to the AmigaOS 4 QEMU guest and run commands there, through the
amiga_mcp devbench MCP server, holding the emulator lock and the "CLAUDE IS TESTING" banner
(the guest is shared with the user and other agents).

    tools/os4guest.py push LOCAL AMIGA_PATH [LOCAL AMIGA_PATH ...]
    tools/os4guest.py dos 'AmigaDOS command'
    tools/os4guest.py test LOCAL_TEST_BINARY [args]   push to RAM:bbtest/ and run it, exit 1 on FAIL
    tools/os4guest.py tool NAME '{json args}'          any devbench MCP tool

Env: OS4_MCP (default http://localhost:3010/mcp; :3000 can be shadowed, see amiga_mcp memory),
AMIGA_MCP (the amiga_mcp checkout, for scripts/claude_busy.py), BB_BANNER=0 to skip the banner.
"""
import contextlib
import json
import os
import shutil
import sys
import tempfile
import urllib.request

URL = os.environ.get("OS4_MCP", "http://localhost:3010/mcp")
AMIGA_MCP = os.environ.get("AMIGA_MCP", os.path.expanduser("~/code/claude_world/amiga_mcp"))


class MCP:
    def __init__(self, url):
        self.url, self.sid = url, None

    def _post(self, body):
        h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.sid:
            h["mcp-session-id"] = self.sid
        with urllib.request.urlopen(urllib.request.Request(self.url, json.dumps(body).encode(), h),
                                    timeout=600) as r:
            raw = r.read().decode()
            self.sid = r.headers.get("mcp-session-id") or self.sid
        msgs = [json.loads(l[5:]) for l in raw.splitlines() if l.startswith("data:")]
        return msgs or ([json.loads(raw)] if raw.strip() else [])

    def tool(self, name, **args):
        if self.sid is None:
            self._post({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {
                "protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "os4guest", "version": "1"}}})
            self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        res = self._post({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                          "params": {"name": name, "arguments": args}})
        r = res[-1].get("result", res[-1]) if res else {}
        text = "\n".join(c.get("text", "") for c in r.get("content", []))
        if r.get("isError"):
            raise RuntimeError(text)
        return text


@contextlib.contextmanager
def testing(message):
    if os.environ.get("BB_BANNER") == "0":
        yield
        return
    sys.path.insert(0, os.path.join(AMIGA_MCP, "scripts"))
    from claude_busy import claude_testing
    with claude_testing(URL, message):
        yield


def push(m, local, dest):
    # ELF files padded to a 1 KB multiple: the bridge's push can wedge on a tiny last chunk
    # (AmiForge tools/m1push.sh); trailing zeros don't matter to the ELF loader.
    src = local
    with open(local, "rb") as f:
        elf = f.read(4) == b"\x7fELF"
    tmp = None
    if elf:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.basename(local))
        tmp.close()
        shutil.copy(local, tmp.name)
        pad = (1024 - os.path.getsize(tmp.name) % 1024) % 1024
        with open(tmp.name, "ab") as f:
            f.write(b"\0" * pad)
        src = tmp.name
    try:
        return m.tool("amiga_push_file", local_path=os.path.abspath(src), amiga_path=dest)
    finally:
        if tmp:
            os.unlink(tmp.name)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd, args = sys.argv[1], sys.argv[2:]
    m = MCP(URL)
    if cmd == "tool":
        print(m.tool(args[0], **(json.loads(args[1]) if len(args) > 1 else {})))
        return 0
    with testing("Boing BASIC tests"):
        if cmd == "push":
            for i in range(0, len(args), 2):
                print(push(m, args[i], args[i + 1]))
        elif cmd == "dos":
            print(m.tool("amiga_dos_command", command=args[0]))
        elif cmd == "test":
            name = os.path.basename(args[0])
            m.tool("amiga_dos_command", command="makedir RAM:bbtest")
            push(m, args[0], "RAM:bbtest/" + name)
            out = m.tool("amiga_dos_command", command=" ".join(["RAM:bbtest/" + name] + args[1:]))
            print(out)
            return 1 if "PASS" not in out else 0
        else:
            print(__doc__)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
