#!/usr/bin/env python3
"""kit.py - the assembly half of tools/make-kit.sh (the builds are in the shell script).

    kit.py plan BB_SRC
        one line per example that goes into the kit:  dir <TAB> bbp <TAB> native(0/1) <TAB> Name
        (bbp relative to examples/dir, empty for a lone .bas)
    kit.py assemble --bb BB_SRC --af AF_SRC --icons AF_ICONS --native NATIVE_DIR --stage STAGE
                    --bb-rev REV --af-rev REV
        builds STAGE/BoingBASIC(.info): AmiForge, boing, lib, include, bindings, Templates, Rexx,
        Docs, Examples/<dir>/ (sources, assets, a .afp project with an icon, <Name>-native if
        NATIVE_DIR/<dir>/<Name> exists), Getting-Started.txt and KIT-MANIFEST.txt.

Paths outside an example's drawer in its .bbp: examples/common/X (and other examples' files) are
copied into the drawer and the line becomes Module=X; bindings/X stays ../../bindings/X, which is
BoingBASIC/bindings in the kit as in the repo.
"""
import importlib.util
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SKIP_DIRS = {"tests", "tools", "bench", "docs", "screenshots", "obj", "build"}
SKIP_EXT = {".o", ".py", ".sh", ".c", ".h", ".exe", ".bbc", ".pyc"}
HELPER_DIRS = {"common"}


# --- examples.txt ---------------------------------------------------------------------------

def read_meta():
    meta, cur = {}, None
    for line in open(os.path.join(HERE, "examples.txt"), encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line.strip())
        if m:
            cur = meta.setdefault(m.group(1), {"keys": []})
            continue
        k, _, v = line.partition("=")
        if cur is None:
            continue
        if k == "keys":
            cur["keys"].append(v)
        else:
            cur[k.strip()] = v.strip()
    return meta


# --- .bbp -----------------------------------------------------------------------------------

def parse_bbp(path):
    b = {"Name": "", "Startup": "", "items": [], "lines": [], "comment": ""}
    for line in open(path, encoding="latin-1"):
        s = line.strip()
        b["lines"].append(line.rstrip("\n"))
        if s.startswith("#"):
            if not b["comment"]:
                c = s.lstrip("# ").strip()
                c = re.sub(r"^Boing BASIC project:?\s*", "", c)
                b["comment"] = c
            continue
        k, _, v = s.partition("=")
        k, v = k.strip(), v.strip()
        if k in ("Module", "Form", "Class"):
            b["items"].append((k, v))
        elif k in ("Name", "Startup", "Stack", "Icon"):
            b[k] = v
    return b


def main_bbp(exdir, name, meta):
    if meta.get("bbp"):
        return meta["bbp"]
    bbps = sorted(f for f in os.listdir(exdir) if f.endswith(".bbp"))
    main = [f for f in bbps if not re.match(r"(?i)(bench|trace|test)", f)]
    if len(main) > 1:
        sys.exit("kit: examples/%s has several projects (%s): set bbp= in tools/kit/examples.txt"
                 % (name, ", ".join(main)))
    return main[0] if main else ""


def examples(bb):
    meta = read_meta()
    out = []
    root = os.path.join(bb, "examples")
    for d in sorted(os.listdir(root)):
        exdir = os.path.join(root, d)
        if d in HELPER_DIRS or not os.path.isdir(exdir):
            continue
        if not any(f.endswith(".bas") for f in os.listdir(exdir)):
            continue
        m = meta.get(d, {"keys": []})
        bbp = main_bbp(exdir, d, m)
        info = parse_bbp(os.path.join(exdir, bbp)) if bbp else None
        name = (info and info["Name"]) or m.get("title") or d.capitalize()
        name = re.sub(r"[^A-Za-z0-9_]", "", name) or d
        kind = m.get("kind") or ("app" if info and info["Startup"].lower().startswith("form") else "console")
        native = m.get("native")
        native = (native == "1") if native is not None else (kind in ("game", "app") and bool(bbp))
        if native and not bbp:
            native = False
        out.append({"dir": d, "bbp": bbp, "info": info, "name": name, "kind": kind, "native": native,
                    "title": m.get("title") or (info and info["Name"]) or name,
                    "about": m.get("about") or (info and info["comment"]) or "",
                    "keys": m.get("keys", []), "meta": d in meta})
    return out


# --- text -----------------------------------------------------------------------------------

SUBST = {"—": "--", "–": "-", "‘": "'", "’": "'", "“": '"', "”": '"', "…": "...", "→": "->",
         "←": "<-", "↔": "<->", "•": "*", " ": " ", "×": "x", "°": " deg", "–": "-"}


def latin1(text):
    for k, v in SUBST.items():
        text = text.replace(k, v)
    return text.encode("latin-1", errors="replace")


def md2txt(src):
    out, fence = [], False
    for line in open(src, encoding="utf-8").read().splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            out.append("    " + line)
            continue
        if line.lstrip().startswith("<!--"):     # the manual's test directives
            continue
        if re.match(r"^\s*!\[", line):            # pictures
            continue
        m = re.match(r"^(#{1,6})\s+(.*)", line)
        if m:
            title = re.sub(r"[`*]", "", m.group(2))
            if out and out[-1] != "":
                out.append("")
            out.append(title.upper() if len(m.group(1)) == 1 else title)
            if len(m.group(1)) <= 2:
                out.append(("=" if len(m.group(1)) == 1 else "-") * len(title))
            continue
        if re.match(r"^\|[-| :]+\|$", line.strip()):
            continue
        if line.strip().startswith("|"):
            line = "  " + "  ".join(c.strip() for c in line.strip().strip("|").split("|"))
        line = re.sub(r"\[([^\]]+)\]\(([^)]+)\)",
                      lambda mm: mm.group(1) if mm.group(1) == mm.group(2) else mm.group(1), line)
        line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)
        line = re.sub(r"\*(.+?)\*", r"\1", line)
        line = line.replace("`", "")
        out.append(line)
    return latin1("\n".join(out).rstrip() + "\n")


def manual_files(bb):
    """The user manual's chapters in reading order: (path, node name)."""
    d = os.path.join(bb, "docs", "manual")
    if not os.path.isdir(d):
        return []
    names = sorted(f for f in os.listdir(d) if f.endswith(".md") and f != "README.md")
    chapters = [f for f in names if f[0].isdigit()] + [f for f in names if not f[0].isdigit()]
    ex = os.path.join(d, "exercises")
    exs = sorted(f for f in os.listdir(ex) if f.endswith(".md") and f != "README.md") if os.path.isdir(ex) else []
    out = [(os.path.join(d, "README.md"), "MAIN")]
    out += [(os.path.join(d, f), f[:-3]) for f in chapters]
    if os.path.exists(os.path.join(ex, "README.md")):
        out.append((os.path.join(ex, "README.md"), "exercises"))
    out += [(os.path.join(ex, f), "exercises-" + f[:-3]) for f in exs]
    return out


def _guide_esc(s):
    return s.replace("\\", "\\\\").replace("@", "\\@")


def md2guide(files, title):
    """One AmigaGuide database of markdown files: a node per file, links between them."""
    nodes = {os.path.normpath(p): n for p, n in files}
    L = ["@database BoingBASIC-Manual.guide", "@author Boing BASIC", "@wordwrap", ""]
    for path, node in files:
        here = os.path.dirname(path)
        text = open(path, encoding="utf-8").read().splitlines()
        first = next((re.sub(r"^#+\s*", "", l) for l in text if l.startswith("#")), node)
        L.append('@node %s "%s"' % (node, _guide_esc(re.sub(r"[`*]", "", first)).replace('"', "'")))
        fence = False
        for line in text:
            if line.lstrip().startswith("```"):
                fence = not fence
                continue
            if line.lstrip().startswith("<!--"):
                continue
            if fence:
                L.append("    " + _guide_esc(line))
                continue
            if re.match(r"^\s*!\[", line):
                continue
            m = re.match(r"^(#{1,6})\s+(.*)", line)
            if m:
                t = _guide_esc(re.sub(r"[`*]", "", m.group(2)))
                L.append("")
                L.append("@{b}%s@{ub}" % (t.upper() if len(m.group(1)) == 1 else t))
                continue
            if re.match(r"^\|[-| :]+\|$", line.strip()):
                continue
            if line.strip().startswith("|"):
                line = "  " + "  ".join(c.strip() for c in line.strip().strip("|").split("|"))
            line = _guide_esc(line)

            def link(mm):
                label, target = mm.group(1), mm.group(2).split("#")[0]
                tgt = os.path.normpath(os.path.join(here, target)) if target else os.path.normpath(path)
                n = nodes.get(tgt)
                return '@{"%s" link %s}' % (label.replace('"', "'"), n) if n else label
            line = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, line)
            line = re.sub(r"\*\*(.+?)\*\*", r"@{b}\1@{ub}", line)
            line = line.replace("`", "")
            L.append(line)
        L.append("@endnode")
        L.append("")
    return latin1("\n".join(L) + "\n")


# --- icons ----------------------------------------------------------------------------------

def make_icons_module(af):
    spec = importlib.util.spec_from_file_location("af_make_icons", os.path.join(af, "tools", "make-icons.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


KIND_COLOURS = {"game": ((150, 90, 230, 255), (70, 30, 140, 255)),
                "app": ((60, 190, 190, 255), (20, 100, 120, 255)),
                "demo": ((250, 160, 60, 255), (170, 70, 20, 255)),
                "console": ((140, 150, 165, 255), (60, 70, 85, 255))}


def native_icon(mi, name, kind, stack):
    """A tool icon for a native build: a rounded tile in the kind's colour, the program's initials,
    and a "NATIVE" strip."""
    from PIL import ImageDraw
    img = mi.canvas()
    S = mi.SS
    top, bottom = KIND_COLOURS.get(kind, KIND_COLOURS["app"])
    from PIL import Image
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([6 * S, 4 * S, 58 * S, 56 * S], radius=9 * S, fill=255)
    mi.gradient_fill(img, mask, top, bottom, 4, 56)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([6 * S, 4 * S, 58 * S, 56 * S], radius=9 * S, outline=(30, 20, 50, 255), width=S)
    caps = re.findall(r"[A-Z0-9]", name)
    initials = caps[0] + caps[1] if len(caps) >= 2 else name[:2].title()
    f = mi.font(24)
    box = d.textbbox((0, 0), initials, font=f)
    x = 32 * S - (box[0] + box[2]) / 2
    y = 25 * S - (box[1] + box[3]) / 2
    d.text((x + S, y + S), initials, font=f, fill=(0, 0, 0, 120))
    d.text((x, y), initials, font=f, fill=(255, 255, 255, 255))
    d.rectangle([6 * S, 44 * S, 58 * S, 54 * S], fill=(255, 214, 90, 255))
    f2 = mi.font(8)
    box = d.textbbox((0, 0), "NATIVE", font=f2)
    d.text((32 * S - (box[0] + box[2]) / 2, 49 * S - (box[1] + box[3]) / 2), "NATIVE", font=f2, fill=(40, 30, 10, 255))
    return mi.disk_object(mi.WBTOOL, mi.finish(img), stack=stack)


def icon_type(path):
    with open(path, "rb") as f:
        data = f.read(64)
    return data[48] if len(data) > 48 and data[:2] == b"\xe3\x10" else 0


# --- assembly -------------------------------------------------------------------------------

def copytree_filtered(src, dst):
    for dirpath, dirnames, filenames in os.walk(src):
        rel = os.path.relpath(dirpath, src)
        dirnames[:] = sorted(d for d in dirnames if d.lower() not in SKIP_DIRS and not d.startswith("."))
        for f in sorted(filenames):
            if f.startswith(".") or os.path.splitext(f)[1].lower() in SKIP_EXT:
                continue
            os.makedirs(os.path.join(dst, rel), exist_ok=True)
            shutil.copy2(os.path.join(dirpath, f), os.path.join(dst, rel, f))


def stage_example(ex, bb, dest, mi, icons, native_dir):
    src = os.path.join(bb, "examples", ex["dir"])
    os.makedirs(dest)
    copytree_filtered(src, dest)
    # files only the other projects (Bench/Trace) use, and those projects, stay out
    keep = set()
    if ex["bbp"]:
        info = ex["info"]
        keep.add(ex["bbp"])
        for k, v in info["items"]:
            keep.add(os.path.normpath(v))
            if k == "Form":
                keep.add(os.path.normpath(v[:-4] + ".bas"))
        for f in os.listdir(src):
            if f.endswith(".bbp") and f != ex["bbp"]:
                for k, v in parse_bbp(os.path.join(src, f))["items"]:
                    p = os.path.normpath(v)
                    if p not in keep and os.path.exists(os.path.join(dest, p)) and "/" not in p:
                        os.unlink(os.path.join(dest, p))
                os.unlink(os.path.join(dest, f))
    # the project file
    if ex["bbp"]:
        bbp_name = ex["bbp"]
        info = ex["info"]
        lines = []
        for line in info["lines"]:
            m = re.match(r"^(\s*)(Module|Form|Class)(\s*=\s*)(\S+)\s*$", line)
            if m:
                v = m.group(4)
                ap = os.path.normpath(os.path.join(src, v))
                if ap.startswith(os.path.normpath(src) + os.sep):
                    pass
                elif ap.startswith(os.path.normpath(os.path.join(bb, "bindings")) + os.sep):
                    v = "../../bindings/" + os.path.relpath(ap, os.path.join(bb, "bindings"))
                elif ap.startswith(os.path.normpath(os.path.join(bb, "examples")) + os.sep):
                    base = os.path.basename(ap)
                    target = os.path.join(dest, base)
                    if os.path.exists(target) and open(target, "rb").read() != open(ap, "rb").read():
                        sys.exit("kit: examples/%s: %s clashes with a file of its own" % (ex["dir"], v))
                    shutil.copy2(ap, target)
                    if m.group(2) == "Form":
                        cb = ap[:-4] + ".bas"
                        if os.path.exists(cb):
                            shutil.copy2(cb, os.path.join(dest, os.path.basename(cb)))
                    v = base
                else:
                    sys.exit("kit: examples/%s: %s is outside the repo's examples and bindings" % (ex["dir"], v))
                line = m.group(1) + m.group(2) + m.group(3) + v
            lines.append(line)
        open(os.path.join(dest, bbp_name), "wb").write(latin1("\n".join(lines) + "\n"))
    else:
        bas = sorted(f for f in os.listdir(dest) if f.endswith(".bas"))
        bbp_name = ex["name"] + ".bbp"
        body = "# Boing BASIC project (made by the kit)\nName=%s\n" % ex["name"]
        body += "".join("Module=%s\n" % f for f in bas)
        open(os.path.join(dest, bbp_name), "wb").write(latin1(body))
    info = parse_bbp(os.path.join(dest, bbp_name))
    # README.md -> README.txt
    readme = None
    if os.path.exists(os.path.join(dest, "README.md")):
        open(os.path.join(dest, "README.txt"), "wb").write(md2txt(os.path.join(dest, "README.md")))
        os.unlink(os.path.join(dest, "README.md"))
        shutil.copy(os.path.join(icons, "doc.info"), os.path.join(dest, "README.txt.info"))
        readme = "README.txt"
    # .afp: what AmiForge's Project::loadBbp makes of the .bbp (modules, then forms with their code)
    files = [bbp_name]
    forms = [v for k, v in info["items"] if k == "Form"]
    for k, v in info["items"]:
        if k == "Module" and v not in files:
            files.append(v)
    for f in forms:
        for x in (f, f[:-4] + ".bas"):
            if x not in files:
                files.append(x)
    for k, v in info["items"]:
        if k == "Class" and v not in files:
            files.append(v)
    for f in sorted(os.listdir(dest)):
        if f.endswith(".cls") and f not in files:
            files.append(f)
    if readme:
        files.append(readme)
    for f in sorted(os.listdir(dest)):
        if f.endswith(".guide") and f not in files:
            files.append(f)
    base = bbp_name[:-4]
    afp = base + ".afp"
    output = base.lower()
    if ex["native"] and output == (ex["name"] + "-native").lower():
        output += "-build"
    text = "# AmiForge project (Boing BASIC kit)\n[project]\nname=%s\noutput=%s\nlanguage=basic\nbbp=%s\n" \
           "stopatmain=0\ndescription=%s\n[files]\n%s" % (
               ex["name"], output, bbp_name, ex["about"], "".join("file=%s\n" % f for f in files))
    open(os.path.join(dest, afp), "wb").write(latin1(text))
    shutil.copy(os.path.join(icons, "project.info"), os.path.join(dest, afp + ".info"))
    # the native build
    nat = None
    built = os.path.join(native_dir, ex["dir"], ex["name"])
    if ex["native"] and os.path.exists(built):
        nat = ex["name"] + "-native"
        shutil.copy2(built, os.path.join(dest, nat))
        os.chmod(os.path.join(dest, nat), 0o755)
        stack = int(info.get("Stack") or 0) or 262144
        own = None
        for d in ("Icons", "icons", "."):
            p = os.path.join(dest, d, ex["name"] + ".info")
            if os.path.exists(p) and icon_type(p) == 3:
                own = p
                break
        if own:
            shutil.copy(own, os.path.join(dest, nat + ".info"))
        else:
            open(os.path.join(dest, nat + ".info"), "wb").write(native_icon(mi, ex["name"], ex["kind"], stack))
    return {"afp": afp, "bbp": bbp_name, "native": nat}


def getting_started(exs, bb_rev, af_rev):
    L = []
    a = L.append
    a("Boing BASIC in AmiForge - getting started")
    a("=========================================")
    a("")
    a("Boing BASIC is a Visual Basic 6 style language for AmigaOS 4. AmiForge is the IDE:")
    a("you draw a window, double-click a button and write what it does.")
    a("")
    a("Start")
    a("  Double-click the AmiForge icon (on the Workbench desktop, or in this drawer).")
    a("  AmiForge finds the Boing BASIC compiler (boing) in this drawer by itself.")
    a("")
    a("Open an example")
    a("  Project > Browse Projects lists every project in the Examples drawer: pick one")
    a("  and Open. (Or double-click a .afp project icon in Examples/<name>/.)")
    a("  - Run (Ctrl-F5, the Run button; F5 too when no breakpoints are set) runs it")
    a("    INTERPRETED: it starts at once, no compiling. Shift-Ctrl-F5 stops it.")
    a("  - Build (F7) makes a NATIVE program with the SDK's GCC. On a QEMU machine that")
    a("    takes several minutes; the Build tab says when it is done.")
    a("  - The games and apps marked [native] below come with a ready native build,")
    a("    <Name>-native in their drawer (most have a yellow NATIVE strip on the icon):")
    a("    double-click it to play at full speed without building anything.")
    a("")
    a("A first program")
    a("  1. Project > New Project from Template > \"Boing BASIC Form App\". Give it a name and")
    a("     save it in MyProjects (a re-install of this kit keeps that drawer).")
    a("  2. In the designer's palette choose \"CommandButton\", click Add.")
    a("  3. Double-click the new button in the Layout list: the editor jumps to")
    a("        Private Sub button1_Click()")
    a("     Type a line there, for example:")
    a("        MsgBox \"Hello from Boing BASIC!\"")
    a("  4. Press Ctrl-F5: the program runs at once in the interpreter. Click your button.")
    a("  5. F7 builds it natively.")
    a("")
    a("Tips")
    a("  - The Events list under the properties shows every event of the selected control;")
    a("    \"code\" marks the ones you have written. Click one to go to its Sub.")
    a("  - Tools > View Form / View Code (Alt-F7) switches between a form and its code.")
    a("  - Errors are clickable in the Build tab; a runtime error goes to its line.")
    a("  - With breakpoints (F9) in a .bas file, F5 builds natively and starts the")
    a("    debugger: step with F10/F11, Locals show your variables.")
    a("")
    a("Examples")
    for kind, head in (("game", "Games"), ("app", "Applications"), ("demo", "Demos"), ("console", "Small programs")):
        group = [e for e in exs if e["kind"] == kind]
        if not group:
            continue
        a("")
        a("  " + head)
        a("  " + "-" * len(head))
        for e in group:
            tag = "  [native: Examples/%s/%s]" % (e["dir"], e["staged"]["native"]) if e["staged"]["native"] else ""
            a("  %s  (Examples/%s/%s)%s" % (e["title"], e["dir"], e["staged"]["afp"], tag))
            if e["about"]:
                a("      " + e["about"])
            for k in e["keys"]:
                a("      " + k)
            if not e["keys"] and kind in ("game", "app") and os.path.exists(e["readme"]):
                a("      Controls: see README.txt in its drawer.")
    a("")
    a("In this drawer")
    a("  AmiForge       the IDE         boing      the Boing BASIC compiler and interpreter")
    a("  include, lib   the runtime for native builds    bindings   OS library declarations")
    a("  Templates      New Project templates           Examples   ready projects")
    a("  Docs           the AmiForge guide and the Boing BASIC language reference")
    a("  MyProjects     your own projects (kept when the kit is installed again)")
    a("")
    a("This kit: Boing BASIC %s, AmiForge %s, made %s." % (bb_rev[:10], af_rev[:10], time.strftime("%Y-%m-%d %H:%M")))
    return latin1("\n".join(L) + "\n")


def assemble(o):
    bb, af, icons = o["bb"], o["af"], o["icons"]
    mi = make_icons_module(af)
    top = os.path.join(o["stage"], "BoingBASIC")
    if os.path.exists(o["stage"]):
        shutil.rmtree(o["stage"])
    os.makedirs(top)
    shutil.copy(os.path.join(icons, "AmiForge-drawer.info"), os.path.join(o["stage"], "BoingBASIC.info"))
    drawer = lambda name: shutil.copy(os.path.join(icons, "drawer.info"), os.path.join(top, name + ".info"))
    # the IDE and the language
    shutil.copy2(os.path.join(af, "build", "AmiForge"), os.path.join(top, "AmiForge"))
    shutil.copy(os.path.join(icons, "AmiForge.info"), os.path.join(top, "AmiForge.info"))
    shutil.copy2(os.path.join(bb, "build", "os4", "boing"), os.path.join(top, "boing"))
    os.makedirs(os.path.join(top, "lib"))
    shutil.copy2(os.path.join(bb, "build", "os4", "libboing.a"), os.path.join(top, "lib", "libboing.a"))
    rt = os.path.join(bb, "src", "runtime")
    for dirpath, _, filenames in os.walk(rt):
        for f in filenames:
            if f.endswith(".h"):
                d = os.path.join(top, "include", os.path.relpath(dirpath, rt))
                os.makedirs(d, exist_ok=True)
                shutil.copy2(os.path.join(dirpath, f), d)
    shutil.copytree(os.path.join(bb, "bindings"), os.path.join(top, "bindings"),
                    ignore=shutil.ignore_patterns("*.md", ".*"))
    drawer("bindings")
    shutil.copytree(os.path.join(af, "templates"), os.path.join(top, "Templates"))
    drawer("Templates")
    if os.path.isdir(os.path.join(af, "Rexx")):
        shutil.copytree(os.path.join(af, "Rexx"), os.path.join(top, "Rexx"))
        drawer("Rexx")
    docs = os.path.join(top, "Docs")
    os.makedirs(docs)
    drawer("Docs")
    for src, name in ((os.path.join(af, "docs", "user-guide.md"), "AmiForge-user-guide.txt"),
                      (os.path.join(bb, "README.md"), "BoingBASIC-README.txt"),
                      (os.path.join(bb, "docs", "language.md"), "BoingBASIC-language.txt"),
                      (os.path.join(bb, "docs", "forms-events.md"), "BoingBASIC-forms-events.txt"),
                      (os.path.join(bb, "docs", "graphics.md"), "BoingBASIC-graphics.txt"),
                      (os.path.join(bb, "docs", "audio.md"), "BoingBASIC-audio.txt"),
                      (os.path.join(bb, "docs", "ui.md"), "BoingBASIC-ui.txt"),
                      (os.path.join(bb, "docs", "engine3d.md"), "BoingBASIC-engine3d.txt")):
        if os.path.exists(src):
            open(os.path.join(docs, name), "wb").write(md2txt(src))
            shutil.copy(os.path.join(icons, "doc.info"), os.path.join(docs, name + ".info"))
    # the user manual: Docs/Manual/ as text (one file per chapter), the AmigaGuide, and the
    # book examples in Examples/Book/
    mf = manual_files(bb)
    if mf:
        mdir = os.path.join(docs, "Manual")
        os.makedirs(mdir)
        drawer("Docs/Manual")
        for src, node in mf:
            name = ("00-contents" if node == "MAIN" else node) + ".txt"
            open(os.path.join(mdir, name), "wb").write(md2txt(src))
            shutil.copy(os.path.join(icons, "doc.info"), os.path.join(mdir, name + ".info"))
        open(os.path.join(docs, "BoingBASIC-Manual.guide"), "wb").write(md2guide(mf, "Boing BASIC user manual"))
        shutil.copy(os.path.join(icons, "doc.info"), os.path.join(docs, "BoingBASIC-Manual.guide.info"))
    # the examples
    exs = examples(bb)
    os.makedirs(os.path.join(top, "Examples"))
    drawer("Examples")
    if os.path.isdir(os.path.join(bb, "examples", "book")):     # every listing and exercise of the manual
        shutil.copytree(os.path.join(bb, "examples", "book"), os.path.join(top, "Examples", "Book"),
                        ignore=shutil.ignore_patterns(".*", "shots"))
        drawer("Examples/Book")
    for e in exs:
        dest = os.path.join(top, "Examples", e["dir"])
        e["staged"] = stage_example(e, bb, dest, mi, icons, o["native"])
        e["readme"] = os.path.join(dest, "README.txt")
        shutil.copy(os.path.join(icons, "drawer.info"), os.path.join(top, "Examples", e["dir"] + ".info"))
    open(os.path.join(top, "Getting-Started.txt"), "wb").write(getting_started(exs, o["bb-rev"], o["af-rev"]))
    shutil.copy(os.path.join(icons, "doc.info"), os.path.join(top, "Getting-Started.txt.info"))
    # the manifest the installer reads
    m = ["# Boing BASIC kit manifest (tools/make-kit.sh)",
         "bb=%s" % o["bb-rev"], "af=%s" % o["af-rev"], "made=%s" % time.strftime("%Y-%m-%dT%H:%M:%S")]
    for e in sorted(set(os.listdir(top)) | {"KIT-MANIFEST.txt"}):   # the manifest itself is written below
        m.append("entry=%s" % e)              # the drawer's top-level entries (install-kit moves these)
    for e in exs:
        m.append("example=%s|%s|%s|%s|%s|%s" % (e["dir"], e["name"], e["kind"], e["staged"]["afp"],
                                                e["staged"]["bbp"], e["staged"]["native"] or "-"))
        if e["native"] and not e["staged"]["native"]:
            m.append("native-failed=%s" % e["dir"])
    open(os.path.join(top, "KIT-MANIFEST.txt"), "wb").write(latin1("\n".join(m) + "\n"))
    for e in exs:
        print("%-16s %-14s %-8s %s" % (e["dir"], e["staged"]["afp"], e["kind"],
                                        e["staged"]["native"] or ("NATIVE FAILED" if e["native"] else "interpreted")))


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "plan":
        for e in examples(sys.argv[2]):
            print("\t".join((e["dir"], e["bbp"], "1" if e["native"] else "0", e["name"])))
        return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "assemble":
        o, a = {}, sys.argv[2:]
        for i in range(0, len(a), 2):
            o[a[i].lstrip("-")] = a[i + 1]
        for k in ("bb", "af", "icons", "native", "stage", "bb-rev", "af-rev"):
            if k not in o:
                sys.exit("kit assemble: --%s missing" % k)
        assemble(o)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
