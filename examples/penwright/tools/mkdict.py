#!/usr/bin/env python3
"""mkdict.py - build Penwright's spelling dictionary (penwright.dict) from web2
(Webster's Second International, public domain, /usr/share/dict/web2 on macOS/BSD) plus
a short list of modern words. One lowercase word per line, sorted by byte value, with a
newline before the first and after the last word (Spell.bas binary-searches the text)."""
import re, sys
src = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/dict/web2"
words = set()
for w in open(src, encoding="latin-1"):
    w = w.strip()
    if re.fullmatch(r"[A-Za-z][a-z]{0,14}", w):     # also capitalised words (Italic, Paris)
        words.add(w.lower())
modern = """a i am an as at be by do go he if in is it me my no of oh ok on or so to up us we
email emails online offline internet website websites web software hardware download downloads
uploaded upload login logout username password passwords computer computers laptop desktop
keyboard mouse printer scanner screenshot smartphone app apps blog blogs podcast video videos
digital database databases spreadsheet spreadsheets workbench amiga amigaos emulator emulators
okay ok etc versus via cannot dont doesnt isnt arent wasnt werent hasnt havent hadnt wont
wouldnt couldnt shouldnt mustnt im ive id youre youve youll youd hes shes its were theyre
theyve theyll theyd thats whats whos wheres theres lets
don't doesn't isn't aren't wasn't weren't hasn't haven't hadn't won't wouldn't couldn't
shouldn't mustn't i'm i've i'd you're you've you'll you'd he's she's it's we're we've
we'll we'd they're they've they'll they'd that's what's who's where's there's let's
color colors colour colours colourful coloured colouring honour honours labour
neighbour neighbours behaviour flavour humour rumour harbour programme programmes
catalogue dialogue travelled travelling cancelled modelling jewellery licence defence
offence favorite favourite center centre organize organise realize
realise analyze analyse theater theatre gray grey toward towards percent per cent
""".split()
words.update(modern)
data = "\n" + "\n".join(sorted(words, key=lambda s: s.encode("latin-1"))) + "\n"
open("penwright.dict", "w", encoding="latin-1", newline="\n").write(data)
print(len(words), "words,", len(data), "bytes")
