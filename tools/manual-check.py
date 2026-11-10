#!/usr/bin/env python3
"""manual-check.py [--verbose] [FILE.md ...] - compile (and run) the code in the user manual.

Every ```basic block in docs/manual/**/*.md is a complete program and is checked with
`boing check`. An HTML comment on the line before the block changes that:

    <!-- run -->          also `boing run` it (the VM) and native-build it; the stdout must
                          equal the ```output (or ```text) block that follows the code
    <!-- run stdin="Ann" -->   the same, with this text (\\n for new lines) as its input
    <!-- fragment -->     not a whole program (a few lines out of a larger one): skipped
    <!-- project: examples/book/ex04-first-form/Converter.bbp -->
                          the block is an excerpt of that project: the project is checked
    <!-- error: 12:5: ... -->  `boing check` must fail with this text in its output

Then the book examples are checked (tools/manual-book.py --check: the generated listings are in
step with the manual), every project under examples/book/ (each .bbp, and each exercise drawer's
.bas) is checked, and the ones with an expected.out are run in the VM (and natively unless
NATIVE=0) and compared.
Exit 1 on any failure. `make manual-test` runs it; `make test` too.
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BOING = os.environ.get("BOING", os.path.join(ROOT, "build", "boing"))
NATIVE = os.environ.get("NATIVE", "1") != "0"
VERBOSE = "--verbose" in sys.argv
ENV = dict(os.environ, BOING_SETTINGS=os.path.join(ROOT, "build", "manual-settings"))

DIRECTIVE = re.compile(r"<!--\s*(run|fragment|project|error)\b:?\s*(.*?)\s*-->")
FENCE = re.compile(r"^```(\w*)\s*$")


def blocks(path):
    """(line, lang, code, directive, arg, expected) for each fenced block."""
    lines = open(path, encoding="utf-8").read().split("\n")
    out, i, pending = [], 0, None
    while i < len(lines):
        m = DIRECTIVE.search(lines[i])
        if m and lines[i].strip().startswith("<!--"):
            pending = (m.group(1), m.group(2))
            i += 1
            continue
        f = FENCE.match(lines[i])
        if f:
            lang, start = f.group(1), i + 1
            j = start
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            code = "\n".join(lines[start:j]) + "\n"
            if lang == "basic":
                d, arg = pending or ("check", "")
                expected = None
                if d == "run":
                    k = j + 1
                    while k < len(lines) and not lines[k].strip():
                        k += 1
                    g = FENCE.match(lines[k]) if k < len(lines) else None
                    if g and g.group(1) in ("output", "text"):
                        e = k + 1
                        while e < len(lines) and not lines[e].startswith("```"):
                            e += 1
                        expected = "\n".join(lines[k + 1:e]) + "\n"
                out.append((start, lang, code, d, arg, expected))
            pending = None
            i = j + 1
            continue
        if lines[i].strip():
            pending = None if not lines[i].strip().startswith("<!--") else pending
        i += 1
    return out


def run(cmd, stdin=None, cwd=None):
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=cwd, env=ENV, timeout=120)
    return r.returncode, r.stdout + r.stderr


def check_program(src, cwd=None):
    return run([BOING, "check", src], cwd=cwd)


def run_program(src, stdin, cwd=None):
    """stdout of the VM and (NATIVE) the native build; both must agree."""
    outs = []
    rc, out = run([BOING, "run", src], stdin, cwd)
    outs.append(("vm", rc, out))
    if NATIVE:
        exe = tempfile.mktemp(prefix="bbman")
        rc, out = run([BOING, "build", src, "-o", exe], cwd=cwd)
        if rc:
            outs.append(("native build", rc, out))
        else:
            rc, out = run([exe], stdin, cwd)
            outs.append(("native", rc, out))
            os.unlink(exe)
    return outs


def main():
    files = [a for a in sys.argv[1:] if a.endswith(".md")] or \
        sorted(glob.glob(os.path.join(ROOT, "docs", "manual", "**", "*.md"), recursive=True))
    failures, counts = [], {"check": 0, "run": 0, "fragment": 0, "project": 0, "error": 0}
    tmpd = tempfile.mkdtemp(prefix="bbmanual")
    for md in files:
        rel = os.path.relpath(md, ROOT)
        for n, (line, lang, code, d, arg, expected) in enumerate(blocks(md)):
            where = "%s:%d" % (rel, line)
            counts[d] = counts.get(d, 0) + 1
            if d == "fragment":
                continue
            if d == "project":
                proj = os.path.join(ROOT, arg)
                rc, out = check_program(proj, cwd=os.path.dirname(proj))
                if rc:
                    failures.append("%s: project %s does not check:\n%s" % (where, arg, out))
                continue
            src = os.path.join(tmpd, "m%d_%d.bas" % (abs(hash(md)) % 100000, n))
            open(src, "w", encoding="latin-1").write(code)
            rc, out = check_program(src, cwd=tmpd)
            if d == "error":
                if rc == 0 or arg not in out:
                    failures.append("%s: expected the error %r, got:\n%s" % (where, arg, out))
                continue
            if rc:
                failures.append("%s: boing check failed:\n%s" % (where, out.replace(src, "<sample>")))
                continue
            if d == "run":
                if expected is None:
                    failures.append("%s: <!-- run --> without an ```output block after it" % where)
                    continue
                m = re.search(r'stdin="(.*?)"', arg)
                stdin = m.group(1).replace("\\n", "\n") + "\n" if m else None
                for kind, rc, out in run_program(src, stdin, cwd=tmpd):
                    if out != expected:
                        failures.append("%s: %s output differs:\n--- expected\n%s--- got (exit %d)\n%s"
                                        % (where, kind, expected, rc, out))
            if VERBOSE:
                print("ok", where, d)
    # the book examples: in step with the manual, and every project in them
    want_projects = not [a for a in sys.argv[1:] if a.endswith(".md")] or "--projects" in sys.argv
    if want_projects:
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "manual-book.py"), "--check"],
                           capture_output=True, text=True)
        if r.returncode:
            failures.append("examples/book is out of step with the manual:\n" + r.stdout)
    book = os.path.join(ROOT, "examples", "book")
    projs = sorted(glob.glob(os.path.join(book, "**", "*.bbp"), recursive=True)) if want_projects else []
    for d in (sorted(glob.glob(os.path.join(book, "ex*", ""))) if want_projects else []):
        if not glob.glob(os.path.join(d, "*.bbp")):
            projs += sorted(glob.glob(os.path.join(d, "*.bas")))[:1]
    for proj in projs:
        d = os.path.dirname(proj)
        rel = os.path.relpath(proj, ROOT)
        rc, out = check_program(proj, cwd=d)
        counts["project"] += 1
        if rc:
            failures.append("%s: boing check failed:\n%s" % (rel, out))
            continue
        exp = os.path.join(d, "expected.out")
        if os.path.exists(exp) and len(glob.glob(os.path.join(d, "*.bbp"))) <= 1:
            inp = os.path.join(d, "input.txt")
            stdin = open(inp).read() if os.path.exists(inp) else None
            want = open(exp).read()
            for kind, rc, out in run_program(proj, stdin, cwd=d):
                if out != want:
                    failures.append("%s: %s output differs from expected.out:\n%s" % (rel, kind, out))
        if VERBOSE:
            print("ok", rel)
    for f in failures:
        print("FAIL", f)
    print("manual: %d checked, %d run, %d projects, %d error samples, %d fragments; %d failures"
          % (counts["check"], counts["run"], counts["project"], counts["error"], counts["fragment"], len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
