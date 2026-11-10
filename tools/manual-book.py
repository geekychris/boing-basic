#!/usr/bin/env python3
"""manual-book.py [--check] - the book examples: every listing of the user manual as a file.

    tools/manual-book.py           write examples/book/chNN-name/listing-NN-MM.bas (+ .out, .in)
                                   for every complete listing in docs/manual/NN-*.md, put a
                                   caption line "*Listing N.M* ..." above each listing in the
                                   manual, and write examples/book/README.md (the index)
    tools/manual-book.py --check   exit 1 if any of that is out of date (make test)

A listing is a ```basic block that is a whole program (no <!-- fragment --> or <!-- error -->
before it). A block marked <!-- project: examples/book/... --> is an excerpt of a project in
the book: it gets a number and its index line points at the project. The exercises' solutions
are the drawers examples/book/exNN-name/ (written by hand, not generated); the chapters'
drawers may hold hand-written projects too (anything not named listing-*).
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MAN = os.path.join(ROOT, "docs", "manual")
BOOK = os.path.join(ROOT, "examples", "book")
sys.path.insert(0, os.path.join(ROOT, "tools"))
CAPTION = re.compile(r"^\*Listing \d+\.\d+\*.*$")
DIRECTIVE = re.compile(r"^\s*<!--\s*(run|fragment|project|error)\b:?\s*(.*?)\s*-->\s*$")
FENCE = re.compile(r"^```(\w*)\s*$")


def chapter_of(md):
    """'04-data.md' -> (4, 'ch04-data'); None for files that aren't numbered chapters."""
    m = re.match(r"^(\d\d)-(.+)\.md$", os.path.basename(md))
    return (int(m.group(1)), "ch%s-%s" % (m.group(1), m.group(2))) if m else None


def process(md):
    """(new markdown text, listings): listings are dicts num, file, code, out, stdin, project, section."""
    num, drawer = chapter_of(md)
    lines = open(md, encoding="utf-8").read().split("\n")
    out, listings, section, i, n = [], [], "", 0, 0
    while i < len(lines):
        line = lines[i]
        if CAPTION.match(line):            # regenerated below
            i += 1
            if i < len(lines) and not lines[i].strip() and out and not out[-1].strip():
                i += 1
            continue
        h = re.match(r"^#{2,3}\s+(.*)", line)
        if h:
            section = re.sub(r"[`*]", "", h.group(1)).strip()
        d = DIRECTIVE.match(line)
        f = FENCE.match(line) if not d else None
        start = None
        if d and i + 1 < len(lines) and FENCE.match(lines[i + 1]) and FENCE.match(lines[i + 1]).group(1) == "basic":
            start, kind, arg = i, d.group(1), d.group(2)
        elif f and f.group(1) == "basic":
            start, kind, arg = i, "check", ""
        if start is not None and kind in ("fragment", "error"):
            j = start + 2                   # copy the directive and its block as they are
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            out.extend(lines[start:j + 1])
            i = j + 1
            continue
        if start is None:
            out.append(line)
            i += 1
            continue
        # the block
        fence_at = start + 1 if kind != "check" else start
        j = fence_at + 1
        while j < len(lines) and not lines[j].startswith("```"):
            j += 1
        code = "\n".join(lines[fence_at + 1:j]) + "\n"
        n += 1
        lst = {"num": "%d.%d" % (num, n), "section": section, "code": code, "project": None,
               "out": None, "stdin": None}
        if kind == "project":
            lst["project"] = arg
            lst["file"] = arg
        else:
            lst["file"] = "examples/book/%s/listing-%02d-%02d.bas" % (drawer, num, n)
        if kind == "run":
            m = re.search(r'stdin="(.*?)"', arg)
            lst["stdin"] = m.group(1).replace("\\n", "\n") + "\n" if m else None
            k = j + 1
            while k < len(lines) and not lines[k].strip():
                k += 1
            g = FENCE.match(lines[k]) if k < len(lines) else None
            if g and g.group(1) in ("output", "text"):
                e = k + 1
                while e < len(lines) and not lines[e].startswith("```"):
                    e += 1
                lst["out"] = "\n".join(lines[k + 1:e]) + "\n"
        listings.append(lst)
        if out and out[-1].strip():
            out.append("")
        out.append("*Listing %s* (`%s`)" % (lst["num"], lst["file"]))
        out.append("")
        out.extend(lines[start:j + 1])
        i = j + 1
    return "\n".join(out), drawer, listings


def main():
    check = "--check" in sys.argv
    stale = []
    index = []
    want = {}
    for md in sorted(glob.glob(os.path.join(MAN, "*.md"))):
        if not chapter_of(md):
            continue
        text, drawer, listings = process(md)
        cur = open(md, encoding="utf-8").read()
        if text != cur:
            if check:
                stale.append(os.path.relpath(md, ROOT) + " (listing captions)")
            else:
                open(md, "w", encoding="utf-8").write(text)
        title = next((l[2:].strip() for l in cur.split("\n") if l.startswith("# ")), drawer)
        index.append((drawer, title, os.path.relpath(md, ROOT), listings))
        for l in listings:
            if l["project"]:
                continue
            base = os.path.join(ROOT, l["file"][:-4])
            want[base + ".bas"] = l["code"]
            if l["out"] is not None:
                want[base + ".out"] = l["out"]
            if l["stdin"] is not None:
                want[base + ".in"] = l["stdin"]
    # exercises: hand-written drawers
    exs = sorted(d for d in glob.glob(os.path.join(BOOK, "ex*", "")))
    L = ["# Boing BASIC user manual: the book examples", "",
         "<!-- Generated by tools/manual-book.py from docs/manual/: do not edit. -->", "",
         "Every complete listing in the [user manual](../../docs/manual/README.md) as a file, and the",
         "solutions of the exercises. Run any of them with `boing run FILE` (`.bas` or `.bbp`), or build",
         "it with `boing build FILE`. Listings that print have the expected output beside them",
         "(`.out`, and `.in` for their input); `tools/manual-check.py` runs them all, interpreted and",
         "native, and checks the others compile.", ""]
    for drawer, title, md, listings in index:
        if not listings:
            continue
        L += ["## %s" % title, "", "[%s](../../%s), drawer `%s/`" % (os.path.basename(md), md, drawer), "",
              "| Listing | File | Section |", "|---|---|---|"]
        for l in listings:
            f = os.path.relpath(os.path.join(ROOT, l["file"]), BOOK)
            L.append("| %s | [%s](%s) | %s |" % (l["num"], f, f, l["section"].replace("|", "\\|")))
        L.append("")
    if exs:
        L += ["## Exercises", "", "| Exercise | Drawer |", "|---|---|"]
        for d in exs:
            name = os.path.basename(os.path.dirname(d))
            projs = sorted(glob.glob(os.path.join(d, "*.bbp")) + glob.glob(os.path.join(d, "*.bas")))
            main = os.path.relpath(projs[0], BOOK) if projs else name + "/"
            L.append("| %s | [%s](%s) |" % (name, main, main))
        L.append("")
    want[os.path.join(BOOK, "README.md")] = "\n".join(L)
    # stale or missing generated files, and generated files no longer wanted
    for path, content in sorted(want.items()):
        cur = open(path, encoding="latin-1").read() if os.path.exists(path) else None
        if cur != content:
            if check:
                stale.append(os.path.relpath(path, ROOT))
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, "w", encoding="latin-1").write(content)
    for path in glob.glob(os.path.join(BOOK, "ch*", "listing-*")):
        if path not in want:
            if check:
                stale.append(os.path.relpath(path, ROOT) + " (no longer in the manual)")
            else:
                os.unlink(path)
    if check:
        for s in stale:
            print("manual-book: out of date:", s)
        if stale:
            print("manual-book: run tools/manual-book.py")
        return 1 if stale else 0
    n = sum(len(x[3]) for x in index)
    print("manual-book: %d listings in %d chapters, %d exercises" % (n, sum(1 for x in index if x[3]), len(exs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
