' Tests of the Penwright document model
Option Explicit

Private Sub Dump(ByVal title As String)
    Dim p As Long
    Print "-- "; title; " ("; NP; "paragraphs)"
    For p = 0 To NP - 1
        Print p; StyleName(pStyle(p)); pAlign(p); " ["; pText(p); "] "; RunsOf(p)
    Next p
End Sub

Sub Main()
    Dim p As Long, o As Long, s As String, n As Long, wl As Long
    NewDoc
    p = 0: o = 0
    InsertText p, o, "Hello world", 0, 12, True
    Print "after typing: p="; p; " o="; o
    InsertText p, o, "!", 0, 12, True
    InsertText p, o, vbLf & "Second line" & vbLf & "Third", 0, 12, False
    Dump "inserted"
    ApplyAttr 0, 0, 0, 5, A_BOLD, A_BOLD
    ApplyAttr 0, 6, 1, 6, A_ITALIC Or A_COLMASK, A_ITALIC Or (6 * 16)
    ApplySize 2, 0, 2, 5, 18
    Dump "styled"
    Print "has bold 0..5: "; RangeHas(0, 0, 0, 5, A_BOLD); " 0..7: "; RangeHas(0, 0, 0, 7, A_BOLD)
    Print "text: "; Replace(GetText(0, 6, 2, 3), vbLf, "|")
    ApplyParaStyle 0, 0, PS_H1
    ApplyAlign 1, 2, AL_CENTER
    Dump "para styles"
    DeleteRange 0, 5, 1, 7
    Dump "deleted"
    Undo
    Dump "undo delete"
    Print "cursor "; UndoCursorP; UndoCursorO
    Undo
    Undo
    Dump "undo x3"
    Redo
    Redo
    Redo
    Dump "redo x3"
    ' typing merges into one undo step
    p = 1: o = 5
    InsertText p, o, " a", 0, 12, True
    InsertText p, o, "b", 0, 12, True
    InsertText p, o, "c", 0, 12, True
    Print "typed: ["; pText(1); "]"
    Undo
    Print "undo typing: ["; pText(1); "]"
    ' styled copy/paste
    s = CopyStyled(0, 0, 1, 4)
    Print "clip: "; Replace(Replace(s, vbLf, "|"), vbTab, " ")
    p = 1: o = Len(pText(1))
    PasteStyled p, o, s
    Dump "pasted"
    Print "end at "; p; o
    ' find / replace
    NewDoc
    p = 0: o = 0
    InsertText p, o, "The cat sat on the mat." & vbLf & "Concatenate the CAT." & vbLf & "the end", 0, 12, False
    p = 0: o = 0
    Print "find cat: "; FindText(p, o, "cat", False, False); p; o
    o = o + 1
    Print "next cat: "; FindText(p, o, "cat", False, False); p; o
    o = o + 1
    Print "next cat: "; FindText(p, o, "cat", False, False); p; o
    p = 0: o = 0
    Print "whole word cat after 1,0: ";
    p = 1: o = 0
    Print FindText(p, o, "cat", False, True); p; o
    p = 0: o = 5
    Print "case CAT: "; FindText(p, o, "CAT", True, False); p; o
    p = 2: o = 4
    Print "wrap the: "; FindText(p, o, "the", True, True); p; o
    n = ReplaceAll("the", "a", False, True)
    Print "replaced "; n; ": "; Replace(AllText(), vbLf, "|")
    Undo
    Print "undo: "; Replace(AllText(), vbLf, "|")
    Print "words "; WordCount(); " chars "; CharCount(True); " no spaces "; CharCount(False)
    Dim ws As Long
    WordAt 0, 6, ws, wl
    Print "word at 0,6: "; Mid$(pText(0), ws + 1, wl); " next word from 4: "; NextWordStart(0, 4); " prev from 8: "; PrevWordStart(0, 8)
    ' files
    NewDoc
    DocTitle = "A <test> & ""quotes"""
    DocAuthor = "Penwright"
    p = 0: o = 0
    InsertText p, o, "Title" & vbLf & "Body text with bold and red." & vbLf & "A quote" & vbLf & "item one" & vbLf & "item two" & vbLf & "x = 1 {code}" & vbLf & "caf" & Chr$(233) & " \ tab" & vbTab & "end", 0, 12, False
    ApplyParaStyle 0, 0, PS_H1
    ApplyAlign 0, 0, AL_CENTER
    ApplyAttr 1, 15, 1, 19, A_BOLD, A_BOLD
    ApplyAttr 1, 24, 1, 27, A_COLMASK, 16
    ApplyParaStyle 2, 2, PS_QUOTE
    ApplyParaStyle 3, 4, PS_BULLET
    ApplyParaStyle 5, 5, PS_CODE
    ApplyAlign 6, 6, AL_JUSTIFY
    s = DocToPwd()
    Print s;
    NewDoc
    Print "pwd back: "; DocFromPwd(s); " same "; (DocToPwd() = s); " title "; DocTitle
    Print DocToHtml();
    Print DocToRtf();
    s = DocToRtf()
    Print "rtf back: "; DocFromRtf(s)
    Dump "from rtf"
    Print DocToText(12);
    ' spelling
    Print "dict: "; LoadDictionary("../../../examples/penwright/penwright.dict", "")
    Dim w As Variant
    For Each w In Array("hello", "Hello", "world", "cats", "running", "stopped", "happily", "tried", "babies", "don't", "computer", "teh", "recieve", "wrold", "xyzzy", "A", "123", "Amiga")
        Print w; "="; CheckWord(w);
    Next w
    Print
    Print "teh -> "; Replace(Suggest("teh", 5), vbLf, " ")
    Print "Recieve -> "; Replace(Suggest("Recieve", 5), vbLf, " ")
    Print "WROLD -> "; Replace(Suggest("WROLD", 5), vbLf, " ")
    NewDoc
    p = 0: o = 0
    InsertText p, o, "This sentense has two mispelt words." & vbLf & "x = teh_var" & vbLf & "Fine text here.", 0, 12, False
    ApplyParaStyle 1, 1, PS_CODE
    p = 0: o = 0
    Do While NextMisspelt(p, o, wl)
        Print "misspelt: "; Mid$(pText(p), o + 1, wl); " at "; p; o
        o = o + wl
    Loop
    AddWord "mispelt"
    p = 0: o = 0
    Print "after AddWord: "; NextMisspelt(p, o, wl); Mid$(pText(p), o + 1, wl)
End Sub
