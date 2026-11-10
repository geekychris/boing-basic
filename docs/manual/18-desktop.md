# The AmigaOS 4 desktop

This chapter is about how a Boing BASIC program fits into the AmigaOS 4 desktop: windows that
adapt to the user's fonts and screen, starting from Workbench or the Shell, icons and tooltypes,
AppIcons and AppWindows, the standard requesters, ARexx, settings, translations, help, and the
conventions Amiga users expect, from the order of the menus to the Amiga-key shortcuts. The
controls themselves are described in [Forms and controls](12-forms.md), and menus, toolbars and
dialogs in detail in [Menus, toolbars, status bars and dialogs](13-menus-dialogs.md); here you
find which of their features to use, and how, so that your program looks and behaves like an
AmigaOS program. Features the system offers but Boing BASIC does not support yet are listed at
the end.

## A well-behaved program at a glance

| Convention | How to do it in Boing BASIC | Section |
|---|---|---|
| windows follow the user's font and screen | lay controls out in rows and columns; don't place them at fixed pixels | [Layouts](#windows-that-fit-any-font-and-screen) |
| windows can be resized, iconified, reopened where they were | `resizable=1`, `iconify=1`, `remember=1` on the `window` line | [Window options](#window-options) |
| works from Workbench and from the Shell | `App.FromWorkbench`, `App.ArgCount`, `App.Arg(i)`, `Command` | [Starting](#started-from-workbench-or-from-the-shell) |
| reads its tooltypes | `App.ToolType("NAME", default)` | [Tooltypes](#tooltypes) |
| gives saved documents an icon | `App.SaveIcon path` | [Icons](#icons) |
| takes files dropped on its window | `dropfiles=1` and `Form_OLEDragDrop` | [AppWindows](#appwindows-files-dropped-on-a-window) |
| uses the system's file, font and screen mode requesters | a `commondialog` control | [ASL requesters](#asl-requesters) |
| asks before throwing work away | `Form_QueryUnload` and a requester | [Requesters](#confirmation-requesters) |
| Project, Edit, Settings menus; Quit last in Project; Amiga-key shortcuts | `menu` objects with `key=` | [Menus](#menus-the-standard-layout) |
| keyboard control | underlined letters, Tab, Esc, Return, Help | [Keyboard](#keyboard-control) |
| an ARexx port | `App.ARexxPort` and `ARexx_Command` | [ARexx](#an-arexx-port) |
| settings in `ENV:` and `ENVARC:` | `GetSetting` / `SaveSetting` | [Settings](#settings-in-env-and-envarc) |
| speaks the user's language | `App.OpenCatalog`, `App.Str`, `$id:` texts | [Catalogs](#translations-catalogs) |
| online help | `App.HelpFile`, `App.ShowHelp` (AmigaGuide) | [Help](#help-amigaguide) |
| a version string | a `$VER:` constant | [Version strings](#version-strings) |

Most of this chapter refers to one example, **Jotter**, a small text editor that follows these
conventions. Its project is in `examples/book/ch18-desktop/jotter/`:

```ini
# Jotter: a small text editor that follows the AmigaOS 4 conventions (manual chapter 18)
Name=Jotter
Startup=Sub Main
Module=Startup.bas
Form=jotter.afg
Stack=262144
```

## Windows that fit any font and screen

An AmigaOS 4 user chooses the screen's resolution and the fonts. One user has a 1920 x 1080
screen with a 16-point font, another a 800 x 600 screen with an 11-point one; a translation can
make every label twice as long. So an AmigaOS program does not put its gadgets at fixed pixel
positions. Boing BASIC forms are built on **ReAction**, AmigaOS 4's gadget toolkit: you describe
the window as nested rows and columns (layout groups), and when the window opens, the layout
asks each gadget how much room it needs *with the current font* and arranges them. The result
fits any font, and the window can be resized.

In a form's `.afg` file (see [Forms and controls](12-forms.md)) a `vlayout` is a column and an
`hlayout` is a row. These keys control how the room is shared:

| Key | On | What it does |
|---|---|---|
| `title="Sound"` | a layout | draws a group frame with that title around the group |
| `frame=group`, `frame=button`, `frame=field` | a layout | a frame without a title, or a raised (`button`) or recessed (`field`) box |
| `even=1` | a layout | all children get the same size (a row of buttons of equal width) |
| `splitter=1` | a layout | the user can drag the bars between the children |
| `label="_Name"` | a control in a layout | a label beside the control, aligned with the other labels of the column |
| `weight=n` | a control or layout | its share of the spare room (default 100 each; `weight=0` keeps it at its smallest size) |
| `minwidth=n`, `minheight=n` | a control or layout | the smallest size in pixels the layout may give it |
| `space` | (an object) | an empty, stretchy gap that pushes its neighbours apart |

When the window grows, the spare room is shared by weight: in a row with weights 30 and 70 the
second child gets more than twice as much as the first. A tool bar or status bar keeps its own
height unless you give it a weight. When the window shrinks, nothing can become smaller than
it needs to show its text in the current font: that is the window's minimum size, and the
window's size gadget stops there.

Here is a settings window from `examples/book/ch18-desktop/prefs/`. It has no pixel position
anywhere; only one `minwidth` so that the number field is wide enough for three digits:

```text
# prefs.afg - an AmigaOS-style settings editor
window name=prefs title="Alarm preferences" width=0 height=0 resizable=1 remember=1
vlayout id=root
  vlayout title="Alarm"
    string id=message label="_Message" text="" hint="The text the alarm shows"
    hlayout
      integer id=minutes label="_Every" value=30 min=1 max=999 minwidth=60
      label text="minutes"
      space
  vlayout title="Sound"
    checkbox id=flash text="_Flash the screen" checked=1
    chooser id=sound label="S_ound" items="None|Bell|Chime" selected=1
  space
  hlayout even=1 weight=0
    button id=save text="_Save" hint="Use the settings and keep them after a reboot"
    space
    button id=use text="_Use" hint="Use the settings until the next reboot"
    space
    button id=cancel text="_Cancel" hint="Close without changing anything"
```

Some rules that keep layouts working everywhere:

- Give the window `width=0 height=0` (or leave them out): the window opens at the smallest
  size its layout needs with the current font. A `width` and `height` are the inner size you
  would like; the window is never made smaller than its layout needs.
- Put related controls in a titled group (`title=`), and labels in `label=` rather than in
  separate `label` objects, so they line up.
- Put the row of buttons at the bottom in an `hlayout even=1 weight=0`: equal buttons, and the
  row doesn't grow when the window does. The left button is the positive action (Save, OK),
  the right one Cancel.
- Give the one control that should take the extra room (a list, a text editor, a canvas) the
  default weight, and its neighbours `weight=0`.
- Don't set the font of a control: every control uses the screen's font, which is what the user
  chose. (Boing BASIC has no font property for controls; a `texteditor` can switch to the
  fixed-width font with `FixedFont`.)
- Make the window resizable unless its contents really have one size (a game at a fixed
  resolution).
- If the layout needs more room than the screen has (a huge form on a small screen, or a big
  font), the window can't open, and `Show` fails with error 7. Use tabs (`tabs`) or a second
  window for large forms.

### Window options

These keys on the `window` line choose the window's gadgets and behaviour:

| Key | Default | What it does |
|---|---|---|
| `title="..."` | `Untitled` | the window title (at run time `Me.Caption`) |
| `width`, `height` | 0 | the inner size you would like, in pixels; 0 = as small as the layout allows |
| `resizable=1` | 1 | a size gadget: the user can resize the window (`resizable=0` for a fixed size) |
| `iconify=1` | 0 | an iconify gadget in the title bar: the window closes and an icon appears on the Workbench; double-clicking the icon opens the window again. From code: `Me.WindowState = 1` iconifies, `0` opens it again. `Form_Resize` runs after both |
| `remember=1` | 0 | the window's position and size are saved when it closes and used when it opens again (in `ENV:` and `ENVARC:`, in a drawer named after the program: `<App.Title>/windows/<form name>`) |
| `toolwindow=1` | 0 | a tool window: no size gadget and no depth gadget (palettes, small floating panels) |
| `dropfiles=1` | 0 | the window is an AppWindow: icons can be dropped on it (see [below](#appwindows-files-dropped-on-a-window)) |
| `contextmenu=menuId` | | the window's context menu (see [Menus](13-menus-dialogs.md)) |

Every window has a close gadget, a drag bar and (unless it is a tool window) a depth gadget.
A window that does not remember its place opens centred on the screen. Closing the window is
the same as `Unload Me`, and goes through `Form_QueryUnload`, where the program can ask
whether to save (see [Confirmation requesters](#confirmation-requesters)).

A program can open further windows (other forms), modal dialogs with `Show vbModal`, and tool
windows: see [Menus, toolbars, status bars and dialogs](13-menus-dialogs.md).

## Screens

Forms open on the **default public screen**. Normally that is the Workbench screen, so your
program appears among the user's other windows. If the user has made another public screen the
default (with a screen manager or a program that opens its own public screen), Boing BASIC
windows open there instead, and so do the requesters they open: requesters always appear on
the form's screen, centred over the active window.

Boing BASIC can't yet open a window on a named public screen or on a screen of its own, and it
has no full-screen or borderless windows: a game is always a window on the desktop. A game
window can still be big: show the picture at 2, 3 or 4 times its size with `scale=` on the
canvas, or let the canvas follow the window's size with `fill=1` (see
[Graphics](14-graphics.md), and [Games on the desktop](#games-on-the-desktop) below).

The screen mode requester exists (`ShowScreenMode`, see [ASL requesters](#asl-requesters)):
a program can let the user choose a mode and keep it in its settings, but there is nothing yet
that opens a screen with it.

## Started from Workbench or from the Shell

An AmigaOS program can be started in two ways, and a good program works with both:

- **From the Shell**, with arguments on the command line: `Jotter Work:Notes/todo.txt`.
- **From Workbench**, by double-clicking its icon, or by double-clicking a document's
  (project) icon whose default tool is the program, or by selecting a few icons with Shift held
  and double-clicking the program's icon last.

These tell you how the program was started and what it was given:

| | What it is |
|---|---|
| `App.FromWorkbench` | `True` if Workbench started the program |
| `App.ArgCount` | the number of files the program was given: the project icons from Workbench, or the words of the command line |
| `App.Arg(i)` | file `i` (from 0) with its full path when it came from Workbench |
| `Command` | the whole command line as one string (empty from Workbench) |
| `App.ToolType(name [, default])` | a tooltype of the program's icon (next section) |
| `App.Path` | the drawer the program is in |

So "open the files I was given" is the same for both: Jotter does it in `Form_Load`.

*Listing 18.1* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub Form_Load()
    mnuFixed.Checked = GetSetting(APPNAME, "Settings", "FixedFont", "0") = "1"
    mnuIcons.Checked = GetSetting(APPNAME, "Settings", "Icons", "1") = "1"
    ed.FixedFont = mnuFixed.Checked
    App.ARexxPort = "JOTTER"                         ' JOTTER.1 if one is running already
    App.HelpFile = App.Path & "/Jotter.guide"        ' the Help key opens it
    If App.ArgCount > 0 Then LoadFile App.Arg(0)     ' a project icon, or "Jotter file" in the Shell
    UpdateTitle
End Sub
```

Things to know about the two ways of starting:

- **No Shell window from Workbench.** A program started from Workbench has no Shell to print
  to. Report problems with a requester (`MsgBox`, `App.Request`), not with `Print`.
- **The current drawer** is not something to rely on: use `App.Path` for the program's own
  files (pictures, help, sounds), and full paths for documents.
- **Stack.** Windows need a stack of at least 256 KB. A native program asks for the `Stack=`
  of its project (262144 by default) with a `$STACK:` cookie in the executable; give its icon
  the same stack size in Workbench's Information window too, as not every way of starting a
  program honours the cookie. In the Shell, `Stack 262144` before starting does the same.
- **Interpreted programs.** `boing` itself does not take a Workbench start. To start a program
  that runs in the interpreter from an icon, write a small script and give the script's icon
  the default tool `C:IconX`:

```sh
; Jotter-run: start Jotter in the interpreter (icon default tool: C:IconX)
Stack 262144
boing run Work:Projects/Jotter/Jotter.bbp
```

  Such a program sees itself as started from the Shell (`App.FromWorkbench` is `False`, and its
  tooltypes are those of the program file's own icon, if it has one). A native build
  (`boing build`) is a real Workbench program, and the better choice for programs you give to
  other people.
- **Ctrl-C.** In the Shell, Ctrl-C stops a program: a console program gets error 18 ("User
  interrupt occurred", which `On Error` can catch); a program with windows closes them and
  ends.

### Tooltypes

Tooltypes are the `NAME=value` lines in an icon's Information window: the Amiga way to give a
program options without a settings window. `App.ToolType("NAME", default)` returns the value
from the program's icon, `"1"` for a bare `NAME` without a value, and the default when the
tooltype is not there. A tooltype in parentheses, `(FONTSIZE=16)`, is switched off: its name is
then `(FONTSIZE`, so it is not found. Started from the Shell, a native program reads the
icon beside its executable, if there is one; without an icon, every tooltype has its default,
so a program written this way works the same both ways:

*Listing 18.2* (`examples/book/ch18-desktop/listing-18-02.bas`)

<!-- run -->
```basic
' Settings from the program's icon, with defaults for a Shell start
Option Explicit
Dim size As Long, pubScreen As String

size = Val(App.ToolType("FONTSIZE", "13"))
pubScreen = App.ToolType("PUBSCREEN", "Workbench")
Print "Font size"; size
Print "Screen: "; pubScreen
If App.FromWorkbench Then
    Print "Started from Workbench"
Else
    Print "Started from the Shell, arguments: """; Command; """"
End If
```

```output
Font size 13 
Screen: Workbench
Started from the Shell, arguments: ""
```

`App.ToolTypeCount` and `App.ToolTypes(i)` give the raw lines (from 0), for a program that wants
to list them all. Tooltype names are written in capitals by convention.

### Icons

Every program and document on the Workbench has an icon, a `.info` file beside it:

- **The program's icon** (a "tool" icon): `Jotter.info` beside the executable `Jotter`. Draw it
  with an icon editor (AmigaOS 4 comes with one), set its stack and tooltypes in the
  Information window, and ship it with the program. The `Icon=` line of a project names it for
  packaging tools.
- **Documents' icons** (project icons): when the program saves a document, it can give it an
  icon whose default tool is the program, so double-clicking the document starts the program
  with it. `App.SaveIcon path [, defaultTool [, template]]` writes `path.info`: the template
  icon's image (a `.info` file, given without `.info`) or the system's default project icon,
  with this program as default tool, or `defaultTool`. Don't replace an icon that is already
  there (the user may have chosen another one), and let the user switch icons off: Jotter has a
  **Settings > Create icons** item for this.

*Listing 18.3* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Function SaveFile(ByVal askName As Boolean) As Boolean
    If askName Or fileName = "" Then
        dlg.DialogTitle = "Save the text as"
        dlg.Flags = cdlOFNOverwritePrompt
        dlg.FileName = fileName
        dlg.ShowSave
        If dlg.Cancelled Then Exit Function
        fileName = dlg.FileName
    End If
    On Error GoTo failed
    ed.SaveFile fileName
    ed.Modified = False
    If mnuIcons.Checked And Dir(fileName & ".info") = "" Then App.SaveIcon fileName
    UpdateTitle
    sb.Text = "Saved"
    SaveFile = True
    Exit Function
failed:
    MsgBox "Can't save " & fileName & vbLf & Err.Description, vbExclamation, APPNAME
End Function
```

A program running in the interpreter is not itself an executable, so pass the default tool
explicitly there: `App.SaveIcon fileName, "Work:Jotter/Jotter"`.

## Workbench integration

### AppWindows: files dropped on a window

With `dropfiles=1` on the `window` line, the form is an **AppWindow**: the user can drag icons
from Workbench and drop them on it. The form's `Form_OLEDragDrop(Count As Integer, X As Integer,
Y As Integer)` runs with the number of icons and the drop position inside the window, and
`App.DropFile(i)` (from 0 to `Count - 1`) is each file's full path. `dropfiles=1` on a single
control makes drops over that control call `<id>_OLEDragDrop` instead, with X and Y inside the
control. `Me.OLEDropMode = 1` turns the AppWindow on from code.

*Listing 18.4* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    If Count > 0 And MayDiscard() Then LoadFile App.DropFile(0)
End Sub
```

### AppIcons and AppMenu items

A program can also put an **AppIcon** on the Workbench (an icon that belongs to the running
program, not to a file) and add items to Workbench's **Tools** menu:

| | What it does |
|---|---|
| `App.ShowAppIcon name [, iconfile]` | shows an AppIcon labelled `name`, with the image of `iconfile` (an icon, with or without `.info`), else the program's own icon, else the default tool icon |
| `App.HideAppIcon` | removes it |
| `AppIcon_DblClick()` | the user double-clicked the AppIcon |
| `AppIcon_DragDrop(Count As Integer)` | icons were dropped on it: `App.DropFile(i)` |
| `App.AddAppMenuItem(text)` | adds an item to Workbench's Tools menu; returns its number (from 0; up to 16 items) |
| `AppMenu_Click(Index As Integer, Count As Integer)` | the item `Index` was chosen, with `Count` icons selected on the Workbench (`App.DropFile(i)`) |

These event procedures (and `ARexx_Command`) can be in any module of the program. A program
with forms gets them while its event loop runs; a program without forms gets them when it calls
`DoEvents`. Here is a complete program without a window: an AppIcon that tells you how big the
files dropped on it are.

*Listing 18.5* (`examples/book/ch18-desktop/listing-18-05.bas`)

```basic
' FileSizes: an AppIcon on the Workbench that tells the size of the files dropped on it,
' and an item in Workbench's Tools menu that does the same for the selected icons
Option Explicit

Private quitting As Boolean

Sub Main()
    App.ShowAppIcon "FileSizes"           ' the program's own icon, or the default tool icon
    App.AddAppMenuItem "File sizes..."
    App.ARexxPort = "FILESIZES"           ' so a script can say: ADDRESS FILESIZES; QUIT
    Do Until quitting
        DoEvents                          ' handles the icon, the menu item and ARexx
        Sleep 50
    Loop
    App.HideAppIcon
End Sub

Private Sub ShowSizes(ByVal count As Integer)
    Dim i As Integer, report As String
    For i = 0 To count - 1
        report = report & App.DropFile(i) & ": " & FileLen(App.DropFile(i)) & " bytes" & vbLf
    Next
    If count > 0 Then App.Request report, "_OK", "FileSizes", vbInformation
End Sub

' files dropped on the AppIcon
Sub AppIcon_DragDrop(Count As Integer)
    ShowSizes Count
End Sub

' the AppIcon double-clicked
Sub AppIcon_DblClick()
    If App.Request("Remove FileSizes from the Workbench?", "_Quit|_Cancel", "FileSizes", vbQuestion) = 1 Then quitting = True
End Sub

' Tools > File sizes... with icons selected
Sub AppMenu_Click(Index As Integer, Count As Integer)
    ShowSizes Count
End Sub

Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    If UCase(Cmd) = "QUIT" Then quitting = True Else App.ARexxRC = 10
End Sub
```

The AppIcon and the menu items are removed when the program ends. A common use of an AppIcon
in a program with a window is to show it while the window is iconified, so that files can
still be dropped on the program.

### Iconifying

`iconify=1` gives the window an iconify gadget. Iconifying closes the window (the form and its
controls stay loaded, timers keep running) and puts an icon with the window's title on the
Workbench; double-clicking it opens the window again where it was. Offer it on every main
window: it is how AmigaOS users tidy their screen. A game should pause while it is iconified
(see [Games on the desktop](#games-on-the-desktop)).

## ASL requesters

Choosing files, fonts and screen modes is done with the system's **ASL requesters**, which the
user already knows (and may have configured: size, position, patterns). In Boing BASIC they are
methods of a `commondialog` control (or of `CreateObject("Boing.CommonDialog")`), described in
detail in [Menus, toolbars, status bars and dialogs](13-menus-dialogs.md):

| Method | Requester |
|---|---|
| `ShowOpen` | the file requester for loading (with `cdlOFNAllowMultiselect`: several files, `FileCount` and `Files(i)`) |
| `ShowSave` | the file requester in save mode; with `cdlOFNOverwritePrompt` it asks before replacing a file |
| `ShowFont` | the font requester (`FontName`, `FontSize`, `FontBold`...) |
| `ShowScreenMode` | the screen mode requester (`ScreenModeID`, `ScreenWidth`, `ScreenHeight`, `ScreenDepth`) |
| `ShowColor` | a colour requester |
| `ShowMessage` | a requester with your own buttons |

Conventions:

- `Filter` takes an AmigaDOS pattern: `#?.(txt|doc)`. Icons (`.info` files) are never shown.
- Remember the drawer: the dialog's `InitDir` follows the user's last choice, so the next
  requester opens where the user was; keep it in your settings to remember it between runs.
- Give each requester a title that says what it is for (`DialogTitle = "Save the text as"`).
- Test `Cancelled` after each `Show...`: cancelling is normal, not an error.
- While a requester is open, the program's windows show a busy pointer and take no input.

## Confirmation requesters

An AmigaOS program never throws the user's work away without asking. Ask when the user closes
the window, quits, or opens or creates another document while the current one has unsaved
changes. `Form_QueryUnload` runs before the window closes (by its close gadget, Quit or
`Unload`); setting `Cancel = True` keeps it open:

*Listing 18.6* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Function MayDiscard() As Boolean
    If Not ed.Modified Then MayDiscard = True: Exit Function
    Select Case dlg.ShowMessage("The text has changed." & vbLf & "Save it first?", _
                                "_Save|_Discard|_Cancel", APPNAME, vbQuestion)
    Case 1: MayDiscard = SaveFile(False)
    Case 2: MayDiscard = True
    Case Else: MayDiscard = False
    End Select
End Function

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If Not MayDiscard() Then Cancel = True
End Sub
```

The requester conventions of AmigaOS:

- Name the buttons after what they do (**Save**, **Discard**, **Cancel**) rather than Yes and
  No. `App.Request(prompt, "_Save|_Discard|_Cancel" [, title [, icon]])` and a CommonDialog's
  `ShowMessage` take your own buttons, separated by `|`, and return the number of the button
  chosen, from 1 at the left. `MsgBox` offers the fixed sets (`vbOKOnly`, `vbYesNo`,
  `vbYesNoCancel`...).
- The positive choice is at the left, the negative one (Cancel) at the right. Esc and the
  close gadget choose the rightmost button, so put the safe choice there.
- Mark a letter of each button with `_`: the user can then answer with the keyboard.
- Give the requester the program's name as its title, and an icon that matches: `vbQuestion`
  for a question, `vbExclamation` for a problem, `vbCritical` for a failure, `vbInformation`
  for a message.

## Menus: the standard layout

Every AmigaOS program has the same first menus, in the same order, so a user finds New, Open,
Save and Quit without looking. The menu bar appears at the top of the screen while the right
mouse button is held down over the window. Jotter's menus follow the AmigaOS style guide:

```text
menu id=mnuProject text="Project"
  menu id=mnuNew text="New" key=N
  menu id=mnuOpen text="Open..." key=O
  menu text=-
  menu id=mnuSave text="Save" key=S
  menu id=mnuSaveAs text="Save as..." key=A
  menu text=-
  menu id=mnuHelp text="Help..."
  menu id=mnuAbout text="About..." key=?
  menu text=-
  menu id=mnuQuit text="Quit" key=Q
menu id=mnuEdit text="Edit"
  menu id=mnuUndo text="Undo" key=Z
  menu id=mnuRedo text="Redo" key=Y
  menu text=-
  menu id=mnuCut text="Cut" key=X
  menu id=mnuCopy text="Copy" key=C
  menu id=mnuPaste text="Paste" key=V
  menu text=-
  menu id=mnuSelAll text="Select all"
menu id=mnuSettings text="Settings"
  menu id=mnuFixed text="Fixed-width font" checkable=1
  menu id=mnuIcons text="Create icons" checkable=1 checked=1
```

- The first menu is **Project** (some programs call it after their documents), with New,
  Open..., Save, Save as..., Print..., About... and **Quit as the last item**.
- Then **Edit** (Undo, Cut, Copy, Paste...), then the program's own menus, then **Settings**
  for options (checkable items) and a Settings window if there is one.
- An item that opens a requester or window ends in `...` (Open..., Save as..., About...).
  An item that acts at once has no dots (Save, Quit).
- Separate groups of items with separator bars (`text=-`).
- Disable items that can't be used now (`mnuSave.Enabled = False`) rather than hiding them, so
  the menus keep their shape.
- Everything a context menu (`contextmenu=`) or a toolbar offers should also be in the menu
  bar: not every user uses the right button over a control, and the menus show the shortcuts.

`key=` gives an item an Amiga-key shortcut: the right Amiga key with that key. Intuition
handles it and shows it in the menu. Use the standard keys for the standard commands, and
don't give them other meanings:

| Shortcut | Command | Shortcut | Command |
|---|---|---|---|
| Amiga-N | New | Amiga-Z | Undo |
| Amiga-O | Open... | Amiga-Y | Redo |
| Amiga-S | Save | Amiga-X | Cut |
| Amiga-A | Save as... | Amiga-C | Copy |
| Amiga-P | Print... | Amiga-V | Paste |
| Amiga-? | About... | Amiga-F | Find |
| Amiga-Q | Quit | | |

Left-Amiga with M and N are the system's (screen switching): leave them alone. How to build
menus, sub-menus, checkable and radio items, change them at run time, and open pop-up menus is
in [Menus, toolbars, status bars and dialogs](13-menus-dialogs.md).

### The right mouse button and context menus

On the Amiga the right mouse button is the menu button: hold it down to see the menu bar. On
AmigaOS 4 a control can also have a **context menu**, a pop-up menu that the right button opens
over that control instead of the menu bar (`contextmenu=mnuEdCtx` names a hidden top-level
`menu`; see [chapter 13](13-menus-dialogs.md)). Jotter's text area has one with Cut, Copy and
Paste. In a paint program or a game the right button may be needed for drawing: `rmb=1` on a
canvas sends the right button to the canvas (as a `MouseDown` with button 2) while the pointer
is over it, and the menus still work everywhere else.

## Keyboard control

An AmigaOS program can be used without the mouse as far as possible:

- **Underlined letters.** A `_` in a button's, checkbox's or label's text underlines the next
  letter: `text="_Save"` shows **S**ave with the S underlined, telling the user which key
  works that gadget. Use a different letter for each gadget of the window. The letters are
  drawn by the gadgets; to make sure the keys work, handle them in `Form_KeyPress`, which runs
  for typed characters while no text field has the input:

*Listing 18.7* (`examples/book/ch18-desktop/prefs/Prefs.bbp`)

<!-- project: examples/book/ch18-desktop/prefs/Prefs.bbp -->
```basic
' the keyboard: Esc is Cancel; the underlined letters work the gadgets
Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    If KeyCode = vbKeyEscape Then cancel_Click
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Select Case UCase(Chr(KeyAscii))
    Case "S": save_Click
    Case "U": use_Click
    Case "C": cancel_Click
    Case "M": message.SetFocus
    Case "E": minutes.SetFocus
    Case "F": flash.Value = 1 - flash.Value
    Case "O": sound.ListIndex = (sound.ListIndex + 1) Mod sound.ListCount
    End Select
End Sub
```

- **Tab** moves from one text or number field to the next (and Shift-Tab back). A text field
  reports Return and Tab in its `KeyPress` event, so Return in a field can start the action
  (`If KeyAscii = 13 Then ...`).
- **Esc** closes a requester or a dialog window as Cancel: do it in `Form_KeyDown` as above.
- **Help** opens the program's help (see [Help](#help-amigaguide)).
- `SetFocus` puts the cursor into a text field, for example the first field when a dialog
  opens.

## Window titles, the busy pointer and hints

- **The window title** names the program and the document: `Jotter: todo.txt`. Mark unsaved
  changes, for example with a `*`, and change the title when the document changes:

*Listing 18.8* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub UpdateTitle()
    Dim name As String
    If fileName = "" Then name = "Untitled" Else name = Mid(fileName, InStrRev(fileName, "/") + 1)
    If InStr(name, ":") > 0 Then name = Mid(name, InStr(name, ":") + 1)
    Me.Caption = APPNAME & ": " & name & IIf(ed.Modified, " *", "")
End Sub
```

- **The busy pointer.** During a long job, show the busy pointer and refuse input:
  `Me.Enabled = False` does both (`True` again at the end), or `Me.MousePointer = vbHourglass`
  only changes the pointer (`vbDefault` to restore it). Call `DoEvents` now and then in a long
  loop, so the window is redrawn and stays movable.
- **Hints.** `hint="..."` on a control (`ToolTipText` at run time) is its help bubble, shown
  when the pointer rests on it. Give a hint to every tool bar button and to controls whose
  purpose is not obvious from their label.

## An ARexx port

ARexx is the Amiga's scripting language, and a program with an **ARexx port** can be driven by
scripts and by other programs. Give every program with documents a port, named after the
program in capitals. Setting `App.ARexxPort` opens it (if the name is taken, because the
program runs twice, it becomes `JOTTER.1` and so on: `App.ARexxPortName` is the name actually
used, worth showing in the About requester). Each command that arrives calls
`ARexx_Command(Cmd As String, Args As String, Result As String)`, with the first word in `Cmd`
and the rest of the line in `Args`:

*Listing 18.9* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Select Case UCase(Cmd)
    Case "OPEN": LoadFile Args
    Case "SAVE": If Not SaveFile(False) Then App.ARexxRC = 5
    Case "GETTEXT": Result = ed.Text
    Case "QUIT": ed.Modified = False: Unload Me
    Case Else: App.ARexxRC = 10
    End Select
End Sub
```

`Result` goes back to the script as `RESULT` (when the script uses `OPTIONS RESULTS`), and
`App.ARexxRC` as `RC`: 0 means success, 5 a warning, 10 an error, 20 a failure. A script then
drives the program like this:

```text
/* jotter-test.rexx */
OPTIONS RESULTS
ADDRESS JOTTER
'OPEN RAM:notes.txt'
'GETTEXT'
SAY 'The text is:' RESULT
```

Conventions: use the standard command names where they fit (NEW, OPEN, SAVE, SAVEAS, PRINT,
QUIT, CUT, COPY, PASTE, HELP), take file names as arguments, and list the commands in your
help. A program sends commands to another program's port with `App.SendARexx(port, command)`,
which returns the `RESULT` (and sets `App.ARexxRC`; error 5 if there is no such port), and
starts a script with `App.RunARexx script`:

*Listing 18.10* (`examples/book/ch18-desktop/listing-18-10.bas`)

```basic
' Ask a running Jotter for its text
Option Explicit
Dim text As String

On Error GoTo noJotter
text = App.SendARexx("JOTTER", "GETTEXT")
Print "Jotter has"; Len(text); "characters (RC"; App.ARexxRC; ")"
End
noJotter:
Print "Jotter is not running"
```

The details are in [Menus, toolbars, status bars and dialogs](13-menus-dialogs.md).

## Settings in ENV: and ENVARC:

AmigaOS keeps programs' settings as small files in two places: `ENVARC:` on disk, which survives
a reboot, and `ENV:`, a copy in RAM that programs read. `SaveSetting app, section, key, value`
writes `ENVARC:app/section/key` and `ENV:app/section/key`, and
`GetSetting(app, section, key [, default])` reads `ENV:` first, then `ENVARC:`, then returns the
default. `DeleteSetting app, section [, key]` removes a setting or a whole section. Use the
program's name as `app`: the user then finds every setting in `ENVARC:Jotter/` (and `remember=1`
windows keep their place in the same drawer). More in [Files and the system](10-files.md).

*Listing 18.11* (`examples/book/ch18-desktop/listing-18-11.bas`)

<!-- run -->
```basic
Option Explicit
SaveSetting "Greeter", "Window", "Colour", "blue"
Print GetSetting("Greeter", "Window", "Colour", "grey")
DeleteSetting "Greeter", "Window", "Colour"
Print GetSetting("Greeter", "Window", "Colour", "grey")
```

```output
blue
grey
```

AmigaOS settings editors (the programs in the `Prefs` drawer) have three buttons at the bottom:
**Save** (use the settings and keep them), **Use** (use them until the next reboot) and
**Cancel**. `SaveSetting` is Save. For Use, write only the `ENV:` file; `GetSetting` finds it
there first:

*Listing 18.12* (`examples/book/ch18-desktop/prefs/Prefs.bbp`)

<!-- project: examples/book/ch18-desktop/prefs/Prefs.bbp -->
```basic
' Use: only ENV: (gone after a reboot); GetSetting reads ENV: first
Private Sub UseSetting(ByVal section As String, ByVal key As String, ByVal value As String)
    Dim f As Integer
    On Error Resume Next                 ' the drawers may exist already
    MkDir "ENV:" & APPNAME
    MkDir "ENV:" & APPNAME & "/" & section
    On Error GoTo 0
    f = FreeFile
    Open "ENV:" & APPNAME & "/" & section & "/" & key For Output As #f
    Print #f, value
    Close #f
End Sub
```

`App.EnvPath` is `ENVARC:` followed by the program's name, for settings files of your own.

## The clipboard

The clipboard is shared by all programs. The text editor control's Cut, Copy and Paste use it
by themselves; elsewhere:

| | |
|---|---|
| `Clipboard.SetText s` | puts text on the clipboard |
| `Clipboard.GetText` | the text on the clipboard (`""` if none) |
| `Clipboard.Clear` | empties it |
| `Clipboard.SetPicture canvas [, imageId]` | puts a canvas's picture (or one of its images) on the clipboard as an IFF ILBM picture, which other picture programs can paste |
| `Clipboard.HasPicture` | `True` if there is a picture on the clipboard |
| `Clipboard.GetPicture(canvas)` | loads the clipboard's picture into the canvas; `True` if there was one |
| `Clipboard.GetImage(canvas)` | the clipboard's picture as a new image of the canvas: its number, 0 if there is none |

Offer the clipboard through the Edit menu with the standard keys (Amiga-X, -C, -V).

## Translations: catalogs

AmigaOS translates programs with **catalogs**: one file per language holding the program's
texts by number, chosen by the user's Locale preferences. A Boing BASIC program uses them like
this:

- `App.OpenCatalog "jotter.catalog" [, builtInLanguage]` opens the catalog for the user's
  preferred languages, and returns `True` if one was found. `builtInLanguage` is the language
  your default texts are written in (`"english"` if you leave it out).
- `App.Str(id, "default")` returns text number `id` from the catalog, or the default when there
  is no catalog or no such text. Keep the numbers in constants.
- In a `.afg` file, any text can be `"$id:default"`, for example `text="$12:Open..."`: the form
  shows catalog text 12, or "Open..." without a catalog. This translates menus, buttons, labels
  and window titles without any code.
- `App.Language` is the language in use (`"english"` without a catalog).

The `.afg` texts are looked up when the form is loaded, so the catalog must be open before
that. A program that starts with a form (`Startup=Form`) loads it first, so a translated program
starts with `Sub Main` instead, opens the catalog, and then shows its window with `Show vbModal`
(which returns when the window is closed, ending the program):

*Listing 18.13* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
' Startup.bas - Jotter starts here (Startup=Sub Main)
Option Explicit

' the version string: the Version command finds it in the native program
Public Const VERSTAG = "$VER: Jotter 1.0 (09.11.2026)"
Public Const APPNAME = "Jotter"

Public Sub Main()
    App.OpenCatalog "jotter.catalog"      ' before the form loads, so its texts are translated
    editor.Show vbModal                   ' returns when the window is closed
End Sub
```

(The form is called `editor` here: a form can't be shown from another module if its name is
also the name of its file's module, or of a procedure such as `Main`.)

In code, translate every text the user sees, and build sentences with placeholders rather than
by joining pieces, because the word order differs between languages:

*Listing 18.14* (`examples/book/ch18-desktop/listing-18-14.bas`)

<!-- run -->
```basic
' Translated strings: the catalog's text if there is one, else the default
Option Explicit
Const MSG_HELLO = 1, MSG_FILES = 2

If App.OpenCatalog("greeter.catalog", "english") Then Print "(catalog open)"
Print App.Str(MSG_HELLO, "Hello!")
Print Replace(App.Str(MSG_FILES, "%1 files"), "%1", CStr(12))
```

```output
Hello!
12 files
```

Catalogs are made with the usual AmigaOS tools (a catalog description and a translation for
each language, compiled with a catalog compiler such as CatComp or FlexCat) and installed as
`LOCALE:Catalogs/<language>/jotter.catalog`, or in a `Catalogs/<language>/` drawer beside the
program (`PROGDIR:Catalogs/`). Programs run by the interpreter have `boing`'s drawer as
`PROGDIR:`, so install their catalogs in `LOCALE:Catalogs`.

## Help: AmigaGuide

AmigaOS help files are AmigaGuide documents (`.guide`), shown by the system's help viewer with
links between nodes. Every program with a window should have one, opened by the **Help** key
and by a Help item in the Project menu:

- `App.HelpFile = App.Path & "/Jotter.guide"` makes the Help key open that file at its `main`
  node, from any of the program's windows.
- `App.ShowHelp file [, node]` opens the help at a node, for a Help menu item or a "?" button.
  The help opens in its own window; the program keeps running.
- Without `App.HelpFile`, the Help key arrives in `Form_KeyDown` as `vbKeyHelp`, so a program
  can do something of its own with it (a game can show its keys).

*Listing 18.15* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub mnuHelp_Click(): App.ShowHelp App.HelpFile, "main": End Sub
```

Give the guide a node for each window or area of the program, and a node listing the ARexx
commands.

## Version strings

The AmigaOS `Version` command, and installers, find a program's version in its file: a text
`$VER: name version.revision (dd.mm.yyyy)`. Put it in a string constant and use the constant
(for example in the About requester), and a native build carries it in the executable, where
`Version Jotter` finds it:

*Listing 18.16* (`examples/book/ch18-desktop/listing-18-16.bas`)

<!-- run -->
```basic
Const VERSTAG = "$VER: Jotter 1.0 (09.11.2026)"
Print Mid(VERSTAG, 7)
```

```output
Jotter 1.0 (09.11.2026)
```

Raise the version when you release a new one, and write the date as day, month and year with
dots. Jotter shows it in its About requester:

*Listing 18.17* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub mnuAbout_Click()
    App.Request Mid(VERSTAG, 7) & vbLf & "A small text editor." & vbLf & _
                "ARexx port: " & App.ARexxPortName, "_OK", "About " & APPNAME, vbInformation
End Sub
```

## Games on the desktop

A game in a window shares the screen with other programs, and should behave like one:

- **Pause when the window is not active.** `Form_Deactivate` runs when the user clicks another
  window; the keys go there now, so pause the game.
- **Pause when iconified**: `Form_Resize` runs, with `Me.WindowState = 1`.
- **Esc asks before quitting**, **P** or Space pauses, **Help** shows the keys.
- **A fixed size**: `resizable=0` for a game drawn at one resolution, and `scale=2` (up to 4) on
  the canvas to show it bigger on today's screens; or `fill=1` on the canvas of a resizable
  window, so the picture follows the window's size (see [Graphics](14-graphics.md)).
- Pace the game with a `timer`, never a busy loop, so other programs keep running.

From `examples/book/ch18-desktop/game/`:

```text
# game.afg - a fixed-size game window, shown at twice its size
window name=game title="Boing Catch" width=0 height=0 resizable=0 iconify=1
vlayout id=root
  canvas id=view width=320 height=200 scale=2
  timer id=tick interval=20
```

*Listing 18.18* (`examples/book/ch18-desktop/game/Game.bbp`)

<!-- project: examples/book/ch18-desktop/game/Game.bbp -->
```basic
' another window was activated: pause, so the player doesn't lose
Private Sub Form_Deactivate()
    paused = True
    DrawFrame
End Sub

Private Sub Form_Resize()
    If Me.WindowState = 1 Then paused = True     ' iconified
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Select Case KeyCode
    Case vbKeyP, vbKeySpace: paused = Not paused
    Case vbKeyHelp: paused = True: MsgBox "Cursor keys: move" & vbLf & "P: pause", vbInformation, "Boing Catch"
    Case vbKeyEscape
        paused = True
        If MsgBox("Quit the game?", vbYesNo + vbQuestion, "Boing Catch") = vbYes Then Unload Me
    End Select
End Sub
```

> **Not yet supported**
>
> These AmigaOS features have no Boing BASIC support yet (some can be reached with `Declare`,
> see [Calling AmigaOS](17-amigaos.md)):
>
> - Opening a window on a named public screen (a `PUBSCREEN` tooltype), or on a screen of the program's own.
> - Full-screen, backdrop or borderless windows (for games); a canvas is always inside a normal window.
> - Using the mode chosen with `ShowScreenMode`: nothing opens a screen with it.
> - The screen title shown while the window is active (`WA_ScreenTitle`).
> - Choosing the font of a window or a control; the font chosen with `ShowFont` can't be applied to controls.
> - Gadget keyboard shortcuts bound by the runtime: the `_` letter is underlined, but the runtime sets no activation key (`GA_ActivateKey`), so the program handles the keys itself.
> - A default button for Return and a Cancel button for Esc in a window: handled in code.
> - Notifications (Ringhio pop-ups through application.library), and registering with application.library (single instance, Quit or Show from other programs); the generated `application.bi` lacks the `APPNOTIFY_` tag constants.
> - Commodities: a hotkey to pop up the window, Show/Hide/Quit from Exchange.
> - A Workbench start of `boing` itself (a project icon with `boing` as default tool): use an IconX script.
> - AmigaDOS argument templates (`ReadArgs`, `FILE/M,PUBSCREEN/K`): parse `Command` yourself.
> - A version string made from the project: the `Version=` and `Title=` lines of a `.bbp` are not used, `App.Major`, `App.Minor` and `App.Revision` are always 0, and `App.Title` is the executable's (or program file's) name, not the project's `Name=`.
> - "Use" for settings: `SaveSetting` always writes both `ENV:` and `ENVARC:`.
> - Context-sensitive help (a guide node per control for the Help key), and gadget help texts shown in a status bar.
> - Number and date formats from the user's Locale preferences: `Format` and the date functions don't follow the locale.
> - Dragging from the program to Workbench or to another program (only dropping onto the program).
> - Clipboard units other than 0, and other clipboard formats than text and IFF pictures.
> - `ShowPalette` (the palette requester).

## Summary

- Lay windows out in groups with weights, never at fixed pixels, so they fit any font and
  screen; offer resizing, iconifying and remembered positions.
- Accept files from Workbench and the Shell (`App.Arg`), read tooltypes with defaults, and give
  saved documents icons with `App.SaveIcon`.
- Use the ASL requesters, ask before discarding work, and name requester buttons after what
  they do.
- Project, Edit, Settings menus with the standard Amiga-key shortcuts; Quit last; `...` on items
  that open a requester; underlined letters, Esc and Help for the keyboard.
- An ARexx port, settings in `ENV:`/`ENVARC:`, catalogs, AmigaGuide help and a `$VER:` string
  make a program a full member of the desktop.

See also: [Forms and controls](12-forms.md), [Menus, toolbars, status bars and
dialogs](13-menus-dialogs.md), [Files and the system](10-files.md),
[Graphics](14-graphics.md), [Calling AmigaOS](17-amigaos.md),
[Networking](19-networking.md), [Extending Boing BASIC](20-extending.md).
