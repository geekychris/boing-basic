#!/usr/bin/env python3
"""manual-pdf-test.py [PDF] - check the PDF of the user manual (make manual-pdf-test): it exists,
has at least MIN_PAGES pages, and (with pdftotext) contains every chapter's, exercise's and
appendix's title."""
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PDF = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "BoingBASIC-Manual.pdf")
MIN_PAGES = 400


def main():
    fails = []
    if not os.path.exists(PDF):
        print("FAIL manual-pdf: %s is missing (make manual-pdf)" % PDF)
        return 1
    pages = 0
    if shutil.which("pdfinfo"):
        info = subprocess.run(["pdfinfo", PDF], capture_output=True, text=True).stdout
        m = re.search(r"^Pages:\s+(\d+)", info, re.M)
        pages = int(m.group(1)) if m else 0
    else:
        pages = open(PDF, "rb").read().count(b"/Type /Page\n") or open(PDF, "rb").read().count(b"/Type/Page")
    if pages < MIN_PAGES:
        fails.append("only %d pages (expected at least %d)" % (pages, MIN_PAGES))
    if shutil.which("pdftotext"):
        text = subprocess.run(["pdftotext", "-layout", PDF, "-"], capture_output=True, text=True).stdout
        flat = re.sub(r"\s+", " ", text)
        for md in sorted(glob.glob(os.path.join(ROOT, "docs", "manual", "*.md")) +
                         glob.glob(os.path.join(ROOT, "docs", "manual", "exercises", "*.md"))):
            if os.path.basename(md) == "README.md" and "exercises" not in md:
                continue
            title = open(md, encoding="utf-8").readline().lstrip("# ").strip()
            title = re.sub(r"^Appendix [A-Z]: ", "", title).replace("`", "")
            if re.sub(r"\s+", " ", title) not in flat:
                fails.append("title not found in the PDF: %s (%s)" % (title, os.path.relpath(md, ROOT)))
    for f in fails:
        print("FAIL manual-pdf:", f)
    print("manual-pdf: %s, %d pages, %d KB%s" % (os.path.relpath(PDF, ROOT), pages, os.path.getsize(PDF) // 1024,
                                               "" if not fails else ", %d failures" % len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
