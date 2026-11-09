' Penwright benchmark: a document of n paragraphs (default 300, ~16 000 words):
' loading the dictionary, laying everything out, drawing a screen, typing a character
' (insert + layout of the paragraph + redraw), spell-checking the whole text, saving.
Option Explicit

Sub Main()
    Dim t0 As Double, i As Long, n As Long, cv As Object, s As String, p As Long, o As Long, wl As Long, bad As Long
    n = 300
    If Command$ <> "" Then n = Val(Command$)
    s = "Penwright lays out each paragraph into lines, with word wrap and alignment, and draws " & _
        "only what is on the screen; a change lays out just the paragraphs it touched, so typing " & _
        "stays quick in long documents. Mispelt words are marked as you type."
    NewDoc
    t0 = TimerMs
    If Not LoadDictionary("../penwright.dict", "") Then LoadDictionary "penwright.dict", ""
    Print "load dictionary: "; Format$((TimerMs - t0), "0"); " ms"
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 660, 430
    ViewInit cv, 660, 430
    LiveSpell = True
    t0 = TimerMs
    p = 0: o = 0
    For i = 1 To n
        InsertText p, o, s & IIf(i < n, vbLf, ""), 0, 12, False
    Next i
    Print "build "; NP; " paragraphs, "; WordCount(); " words: "; Format$((TimerMs - t0), "0"); " ms"
    Dim h As Long
    t0 = TimerMs
    SyncLayout
    h = DocHeight()
    Print "lay out all: "; Format$((TimerMs - t0), "0.0"); " ms, height "; h; " px"
    t0 = TimerMs
    For i = 1 To 20
        scrollY = i * 400
        DrawDoc cv
    Next i
    Print "draw a screen (scrolled, with spelling marks): "; Format$((TimerMs - t0) / 20, "0.0"); " ms"
    SetCursor 150, 40, False
    EnsureCaretVisible
    t0 = TimerMs
    For i = 1 To 50
        TypeText "x", True
        DrawDoc cv
    Next i
    Print "type a character + redraw: "; Format$((TimerMs - t0) / 50, "0.0"); " ms"
    t0 = TimerMs
    p = 0: o = 0
    Do While NextMisspelt(p, o, wl)
        bad = bad + 1
        o = o + wl
    Loop
    Print "spell-check all: "; Format$((TimerMs - t0), "0"); " ms, "; bad; " misspelt"
    t0 = TimerMs
    s = DocToPwd()
    Print "serialize .pwd: "; Format$((TimerMs - t0), "0"); " ms, "; Len(s); " bytes"
    t0 = TimerMs
    s = DocToRtf()
    Print "RTF export: "; Format$((TimerMs - t0), "0"); " ms, "; Len(s); " bytes"
End Sub
