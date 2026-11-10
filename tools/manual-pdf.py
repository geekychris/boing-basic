#!/usr/bin/env python3
"""manual-pdf.py [--letter] [--out FILE] - the user manual as a PDF book.

The source stays docs/manual/*.md. Each file is converted with pandoc (gfm -> asciidoc) into
build/manual-adoc/, fixed up for a book (chapter ids, internal links, listing titles, BASIC
highlighting, figures with captions), and a master file book.adoc includes them in parts. Then
asciidoctor-pdf renders build/BoingBASIC-Manual.pdf with tools/manual-pdf-theme.yml; any
asciidoctor warning (an unresolved link, a missing image) fails the build.

    tools/manual-pdf.py              A4
    tools/manual-pdf.py --letter     US Letter
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MAN = os.path.join(ROOT, "docs", "manual")
OUT = os.path.join(ROOT, "build", "manual-adoc")
PANDOC = shutil.which("pandoc") or "/opt/homebrew/bin/pandoc"
ASCIIDOCTOR_PDF = shutil.which("asciidoctor-pdf") or "/opt/homebrew/bin/asciidoctor-pdf"
REPO_URL = "https://github.com/geekychris/boing-basic/blob/main/"

PARTS = [
    ("Using Boing BASIC", ["01-introduction", "02-shell", "03-amiforge"]),
    ("The language", ["04-data", "05-procedures", "06-control-flow", "07-expressions", "08-errors",
                      "09-builtins", "10-files", "11-classes"]),
    ("Programs with windows", ["12-forms", "13-menus-dialogs", "14-graphics", "15-engine3d",
                               "16-audio", "17-amigaos", "18-desktop"]),
    ("Networking and libraries", ["19-networking", "20-libraries"]),
    ("Extending", ["21-extending"]),
]
EXERCISES = ["exercises/README", "exercises/01-console", "exercises/02-adventure", "exercises/03-classes",
             "exercises/04-first-form", "exercises/05-notes-app", "exercises/06-canvas-game",
             "exercises/07-3d-scene", "exercises/08-sound", "exercises/09-extending"]
APPENDICES = ["appendix-a-keywords", "appendix-b-functions", "appendix-c-errors"]


def stem_id(stem):
    """'exercises/04-first-form' -> 'ex-04-first-form', '12-forms' -> 'ch-12-forms'."""
    if stem.startswith("exercises/"):
        return "ex-" + stem.split("/", 1)[1].lower()
    if stem.startswith("appendix"):
        return stem.lower()
    return "ch-" + stem.lower()


def gh_slug(title):
    """The anchor GitHub gives a heading (as the manual's links use them)."""
    t = re.sub(r"[`*]", "", title.strip().lower())
    t = re.sub(r"[^\w\- ]", "", t)
    return t.replace(" ", "-")


def all_stems():
    out = [s for _, ch in PARTS for s in ch] + EXERCISES + APPENDICES
    return out


CODE_TOKEN = "BBCODESPAN%dX"


def code_spans(md):
    """The inline code spans of a Markdown text (outside fenced blocks), as written: a list of
    (start, end, text) with the text as the reader sees it (table-cell \\| unescaped)."""
    out, fence, pos = [], False, 0
    for line in md.split("\n"):
        if line.lstrip().startswith("```"):
            fence = not fence
        elif not fence:
            for m in re.finditer(r"(`+)(.+?)(?<!`)\1(?!`)", line):
                text = m.group(2)
                if text.startswith(" ") and text.endswith(" ") and text.strip():
                    text = text[1:-1]
                if line.lstrip().startswith("|"):
                    text = text.replace("\\|", "|")
                out.append((pos + m.start(), pos + m.end(), text))
        pos += len(line) + 1
    return out


def protect_code_spans(md):
    """Replace inline code with tokens pandoc leaves alone: AsciiDoc would read #, ^, ~, *, _,
    + and {name} inside backticks as markup."""
    spans = code_spans(md)
    texts = []
    for start, end, text in reversed(spans):
        texts.append(text)
        md = md[:start] + CODE_TOKEN % (len(spans) - len(texts)) + md[end:]
    texts.reverse()
    return md, texts


def restore_code_spans(adoc, texts):
    """Each token -> monospace text passed through as it is (only <, > and & escaped). In a
    table row a | is escaped, or it would end the cell."""
    out = []
    for line in adoc.split("\n"):
        cell = line.startswith("|")

        def put(mm):
            t = texts[int(mm.group(1))]
            if cell:
                t = t.replace("|", "\\|")
            core = t.rstrip("\\")          # pass:c[...\] would read as an escaped ]: trailing
            tail = "{backslash}" * (len(t) - len(core))   # backslashes go outside the macro
            return "``%s%s``" % ("pass:c[%s]" % core.replace("]", "\\]") if core else "", tail)
        out.append(re.sub(r"BBCODESPAN(\d+)X", put, line))
    return "\n".join(out)


def convert(stem, known):
    src = os.path.join(MAN, stem + ".md")
    md = open(src, encoding="utf-8").read()
    md = re.sub(r"<!--.*?-->\n?", "", md, flags=re.S)          # the manual-check directives
    md, spans = protect_code_spans(md)
    adoc = subprocess.run([PANDOC, "-f", "gfm", "-t", "asciidoc", "--wrap=none"], input=md,
                          capture_output=True, text=True, check=True).stdout
    here = os.path.dirname(src)
    sid = stem_id(stem)
    lines = adoc.split("\n")
    out, seen, first = [], {}, True
    for line in lines:
        m = re.match(r"^(=+) (.*)$", line)
        if m:
            title = m.group(2)
            plain = re.sub(r"BBCODESPAN(\d+)X", lambda mm: spans[int(mm.group(1))], title)
            slug = gh_slug(re.sub(r"\[.*?\]|link:\S+", "", plain))
            n = seen.get(slug, 0)
            seen[slug] = n + 1
            anchor = sid if first else "%s-%s" % (sid, slug + ("-%d" % n if n else ""))
            if first:
                # chapter titles: "Appendix A: Keywords" -> "Keywords" (asciidoctor adds the letter)
                title = re.sub(r"^Appendix [A-Z]: ", "", title)
            out.append("[[%s]]" % anchor)
            out.append("%s %s" % (m.group(1), title))
            first = False
            continue
        out.append(line)
    adoc = "\n".join(out)

    # links between the manual's files -> internal cross references
    def link(mm):
        target, text = mm.group(1), mm.group(2)
        path, _, anchor = target.partition("#")
        if not path:
            dest = os.path.normpath(src)
        else:
            dest = os.path.normpath(os.path.join(here, path))
        rel = os.path.relpath(dest, MAN)
        if rel.endswith(".md"):
            st = rel[:-3]
            if st in known:
                xid = stem_id(st) + ("-" + anchor if anchor else "")
                return "xref:%s[%s]" % (xid, text)
            if st == "README":                                   # the contents page
                return text
        # a file of the repository: link to it on GitHub
        repo_rel = os.path.relpath(dest, ROOT)
        return "%s%s[%s]" % (REPO_URL, repo_rel, text)
    adoc = re.sub(r"link:([^\[\s]+)\[([^\]]*)\]", link, adoc)

    # "Listing N.M (path)" paragraphs -> the title of the block that follows
    adoc = re.sub(r"_Listing (\d+\.\d+)_ \(`([^`]+)`\)\n\n\[source,basic\]",
                  lambda mm: ".Listing %s (`%s`)\n[source,basic]" % (mm.group(1), mm.group(2)), adoc)
    adoc = adoc.replace("[source,basic]", "[source,boingbasic]")   # tools/manual-pdf-lexer.rb
    adoc = re.sub(r"\[source,(output|text)\]", "[listing]", adoc)

    # pictures: a paragraph that is only an image -> a figure, captioned by the italic line after it
    def figure(mm):
        path, alt, cap = mm.group(1), mm.group(2), mm.group(4)
        full = os.path.normpath(os.path.join(here, path))
        title = cap if cap else alt
        return ".%s\nimage::%s[%s]\n" % (title, full, alt.replace(",", ""))
    adoc = re.sub(r"^image:([^\[\s]+)\[([^\]]*)\]\n(\n_([^\n]+)_\n)?", figure, adoc, flags=re.M)
    adoc = restore_code_spans(adoc, spans)
    open(os.path.join(OUT, stem.replace("/", "_") + ".adoc"), "w", encoding="utf-8").write(adoc)


def version():
    if os.environ.get("MANUAL_VERSION"):
        return os.environ["MANUAL_VERSION"]
    try:
        return subprocess.run(["git", "-C", ROOT, "describe", "--tags", "--always", "--dirty"],
                              capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return "unknown"


def master(letter):
    import datetime
    L = ["= Boing BASIC: A structured BASIC for AmigaOS 4",
         ":doctype: book",
         ":revnumber: " + version(),
         ":revdate: " + datetime.date.today().isoformat(),
         ":toc:", ":toclevels: 2", ":sectnums:", ":sectnumlevels: 1", ":partnums!:",
         ":chapter-signifier: Chapter",
         ":source-highlighter: rouge", ":rouge-style: github",
         ":pdf-theme: manual-pdf-theme.yml", ":pdf-themesdir: " + os.path.join(ROOT, "tools"),
         ":pdf-page-size: " + ("Letter" if letter else "A4"),
         ":title-logo-image: image:" + os.path.join(MAN, "images", "boing-ball.png") + "[pdfwidth=45%,align=center]",
         ":icons: font", ":experimental:", ":hide-uri-scheme:",
         ":listing-caption!:", ":figure-caption!:", ":table-caption!:",
         ""]
    for title, chapters in PARTS:
        L += ["= " + title, ""]
        for c in chapters:
            L += ["include::%s.adoc[leveloffset=0]" % c.replace("/", "_"), ""]
    L += ["= Exercises", "", ":sectnums!:", ""]
    for c in EXERCISES:
        L += ["include::%s.adoc[]" % c.replace("/", "_"), ""]
    L += [":sectnums:", ""]
    for c in APPENDICES:
        L += ["[appendix]", "include::%s.adoc[]" % c, ""]
    open(os.path.join(OUT, "book.adoc"), "w", encoding="utf-8").write("\n".join(L))


def main():
    letter = "--letter" in sys.argv
    out = os.path.join(ROOT, "build", "BoingBASIC-Manual%s.pdf" % ("-Letter" if letter else ""))
    if "--out" in sys.argv:
        out = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    known = set(all_stems())
    for st in known:
        convert(st, known)
    master(letter)
    r = subprocess.run([ASCIIDOCTOR_PDF, "-v", "-r", os.path.join(ROOT, "tools", "manual-pdf-lexer.rb"), "--failure-level=WARN", "-o", out, os.path.join(OUT, "book.adoc")],
                       capture_output=True, text=True)
    sys.stderr.write(r.stderr)
    if "possible invalid reference" in r.stderr:     # asciidoctor reports these only as INFO
        print("manual-pdf: unresolved cross references (see above)", file=sys.stderr)
        return 1
    if r.returncode:
        print("manual-pdf: asciidoctor-pdf failed (warnings count as errors)", file=sys.stderr)
        return 1
    qpdf = shutil.which("qpdf")
    if qpdf:                              # asciidoctor-pdf leaves most streams uncompressed
        tmp = out + ".tmp"
        subprocess.run([qpdf, "--compress-streams=y", "--recompress-flate", "--object-streams=generate",
                        out, tmp], check=True)
        os.replace(tmp, out)
    print("manual-pdf: wrote %s (%d KB)" % (os.path.relpath(out, ROOT), os.path.getsize(out) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
