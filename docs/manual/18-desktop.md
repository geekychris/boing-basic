# The AmigaOS 4 desktop

This chapter is about how a Boing BASIC program fits into the AmigaOS 4 desktop: windows that
adapt to the user's fonts and screen, starting from Workbench or the Shell, arguments, icons and
tooltypes, AppIcons and AppWindows, the standard requesters, ARexx, notifications, hotkeys and
Exchange, settings, the clipboard, translations, number and date formats, help, and the conventions Amiga users expect, from the order of the menus to the Amiga-key shortcuts. The
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
| opens on the screen the user wants, or on a screen of its own | `pubscreen=`, `screen=own`, `App.OpenScreen` | [Screens](#screens) |
| uses the user's fonts, or a font the user picked | no `font=` as a rule; `Me.FontName` after `ShowFont` | [Fonts](#fonts) |
| works from Workbench and from the Shell | `App.FromWorkbench`, `App.ArgCount`, `App.Arg(i)`, `Command` | [Starting](#started-from-workbench-or-from-the-shell) |
| reads its tooltypes | `App.ToolType("NAME", default)` | [Tooltypes](#tooltypes) |
| takes its options as an AmigaDOS template, or as tooltypes from Workbench | `App.ReadArgs("FILE/A,SIZE/N,QUIET/S")`, `App.ArgValue("FILE")` | [Arguments](#arguments-templates-and-tooltypes) |
| an interpreted program starts from its icon | a project icon with the default tool `boing` | [From Workbench](#interpreted-programs-from-workbench) |
| gives saved documents an icon | `App.SaveIcon path` | [Icons](#icons) |
| takes files dropped on its window | `dropfiles=1` and `Form_OLEDragDrop` | [AppWindows](#appwindows-files-dropped-on-a-window) |
| uses the system's file, font and screen mode requesters | a `commondialog` control | [ASL requesters](#asl-requesters) |
| asks before throwing work away | `Form_QueryUnload` and a requester | [Requesters](#confirmation-requesters) |
| Project, Edit, Settings menus; Quit last in Project; Amiga-key shortcuts | `menu` objects with `key=` | [Menus](#menus-the-standard-layout) |
| keyboard control | `_` shortcut letters, `default=1` and `cancel=1` buttons, Tab, Help | [Keyboard](#keyboard-control) |
| a help line that says what the control under the pointer does | `hint=` on the controls, `statusbar hints=1` | [Hints](#window-titles-the-busy-pointer-and-hints) |
| an ARexx port | `App.ARexxPort` and `ARexx_Command` | [ARexx](#an-arexx-port) |
| tells the user something without stopping them | `App.Notify title, text` (a Ringhio notification) | [Notifications](#notifications) |
| a hotkey, and an entry in Exchange that can show, hide and quit it | `App.HotKey`, `HotKey_Pressed`, `App_Show`, `App_Hide`, `App_Quit` | [Commodities](#commodities-a-hotkey-and-exchange) |
| settings in `ENV:` and `ENVARC:`, with Save, Use and Cancel | `GetSetting`, `SaveSetting`, `UseSetting` | [Settings](#settings-in-env-and-envarc) |
| copies and pastes through the clipboard | `Clipboard.SetText`, `GetText`, `SetPicture`... | [Clipboard](#the-clipboard) |
| speaks the user's language | `App.OpenCatalog`, `App.Str`, `$id:` texts | [Catalogs](#translations-catalogs) |
| shows numbers and dates the way the user set them in Locale | `App.FormatNumber`, `App.FormatDate` | [Formats](#number-and-date-formats) |
| online help, for the control under the pointer | `App.HelpFile`, `helpnode=`, `App.ShowHelp` (AmigaGuide) | [Help](#help-amigaguide) |
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
    string id=message label="_Message" hint="The text the alarm shows"
    hlayout
      integer id=minutes label="_Every" value=30 min=1 max=999 minwidth=60
      label text="minutes"
      space
  vlayout title="Sound"
    checkbox id=flash text="_Flash the screen" checked=1
    chooser id=sound label="S_ound" items="None|Bell|Chime" selected=1
  space
  hlayout even=1 weight=0
    button id=save text="_Save" default=1 hint="Use the settings and keep them after a reboot"
    space
    button id=use text="_Use" hint="Use the settings until the next reboot"
    space
    button id=cancel text="_Cancel" cancel=1 hint="Close without changing anything"
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
- Leave the fonts alone: without `font=`, every control uses the screen's font, which is what
  the user chose. Set a font only for a reason, such as a large display or a font the user
  picked in your program's settings (see [Fonts](#fonts)).
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
| `contextmenu=menuId` | | the window's context menu (see [below](#the-right-mouse-button-and-context-menus)) |
| `contextmenukey=always` | | context menus open with a plain right click instead of Shift or Ctrl + right button |
| `screentitle="..."` | | the screen's title bar text while this window is the active one (at run time `Me.ScreenTitle`) |
| `pubscreen="Name"`, `screen=own` | | the screen the window opens on (see [Screens](#screens)) |
| `fullscreen=1` | 0 | a window without border or gadgets that covers its whole screen (see [Screens](#screens)) |
| `borderless=1` | 0 | a window without border, title bar or gadgets, at its normal size and place |
| `backdrop=1` | 0 | a backdrop window: it stays behind every other window of its screen |
| `font="Name"`, `fontsize=n` | | the font of the window and its controls (see [Fonts](#fonts)) |

A normal window has a close gadget, a drag bar and (unless it is a tool window) a depth gadget.
A `borderless=1` or `fullscreen=1` window has none of them, not even a close gadget: give the
user another way out (a Quit menu item, a button, or Esc). A window that does not remember its
place opens centred on the screen. Closing the window is
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

That is right for almost every program. The keys on the `window` line choose another screen:

| Key | What it does |
|---|---|
| `pubscreen="Name"` | the window opens on the public screen with that name. If there is no such screen, it opens on the default public screen |
| `screen=own` | the window opens on the program's **own screen**, which the program opens first if it isn't open yet |
| `screenmode=0x...` | with `screen=own`: the screen mode, a `ScreenModeID` number as the screen mode requester returns it. Without it, the screen has the Workbench's mode |
| `screenwidth=`, `screenheight=`, `screendepth=` | with `screen=own`: the screen's size in pixels and its depth (16 for 65536 colours, 24 or 32 for true colour); without them, those of the Workbench |
| `screentitle="..."` | the text in the screen's title bar while the window is active; with `screen=own` also the title of the new screen |
| `screen=workbench` | this window stays on the default public screen even when the program has its own screen |
| `fullscreen=1` | the window has no border and no gadgets and covers its whole screen |

The program's own screen is a public screen, shared by all its windows: once it is open, every
form that is loaded afterwards opens on it (unless its `window` line says `screen=workbench`),
and so do the requesters, `MsgBox` and the ASL requesters, which always appear on the screen of
the program's active window. The screen stays open until the program ends. To close it earlier,
close (unload) its windows and call `App.CloseScreen`, which returns `True` if the screen was
closed (or wasn't open) and `False` while a window is still open on it.

A program can also open its own screen in code, with a mode the user chose:

| | What it does |
|---|---|
| `App.OpenScreen modeid [, width, height, depth [, title [, showTitle]]]` | opens the program's own screen: `modeid` is a `ScreenModeID` (0 for the Workbench's mode); a width, height or depth of 0 (or left out) means the Workbench's. `title` is the screen's title (else `App.Title`). `showTitle = False` opens it without a title bar (the default is `True`). Error 5 if the screen can't be opened, and error 5 if the program's screen is already open: call `App.CloseScreen` first to open it in another mode |
| `App.CloseScreen` | closes the program's own screen if no window is open on it; returns `True` when it is closed |

The mode usually comes from the screen mode requester (`ShowScreenMode`, see
[ASL requesters](#asl-requesters)), and the program keeps it in its settings. Open the screen
*before* the forms that should appear on it are loaded: a form takes its screen when it is
loaded, and a window that is already open stays where it is. A program that starts with a form
(`Startup=Form`) has loaded it before any of its code runs, so such a program starts with
`Sub Main`, opens the screen, and then shows its form; the full-screen game
[at the end of this chapter](#a-full-screen-game-on-its-own-screen) does this.

A screen opened with `App.OpenScreen` has a title bar unless its `showTitle` argument is
`False`. A `fullscreen=1` window on the program's own screen hides that screen's title bar,
however the screen was opened, so the window really covers the whole screen.

Pictures on buttons, toolbar buttons and `image` controls are made for the colours of the
screen the form opens on, and a grid's rows fit the window's font (or that screen's font), so
they look right on the program's own screen as well as on the Workbench.

Use your own screen for programs that need it: a game in a particular resolution, a program
that needs more room or colours than the Workbench has. Ordinary programs belong on the
Workbench or on the public screen the user has chosen.

## Fonts

Without a font of its own, a window and all its controls use the screen's font, the one the
user chose in the Font preferences. That is the right choice for most windows. When you have a
reason to choose (a calculator's large display, a program whose settings let the user pick a
font), these keys set a font:

| Key | On | What it does |
|---|---|---|
| `font="DejaVu Sans"` | the `window` line | the font of the window and of every control in it; the name is written without `.font` |
| `fontsize=13` | the `window` line | its size in pixels (13 if only `font=` is given). With only `fontsize=`, the window keeps the screen's font at that size |
| `font=`, `fontsize=` | a control | a font for that control alone. With only `fontsize=`, the control takes the window's font (or the screen's font) at that size |

If the font isn't installed, the window or control quietly keeps the screen's font. The layout
measures every control with its own font, so a window with a large font is simply a larger
window.

At run time `Me.FontName` and `Me.FontSize` are the window's font (`""` and 0 when it has none
of its own). Setting either one gives the window and its controls the new font and lays the
window out again; controls with a `font=` of their own keep theirs. Setting only
`Me.FontSize` on a window without a `font=` keeps the screen's font at the new size. A font that
can't be opened is error 380. This is how a program applies the font the user chose in the font requester:

<!-- fragment -->
```basic
dlg.ShowFont
If Not dlg.Cancelled Then
    Me.FontName = dlg.FontName
    Me.FontSize = dlg.FontSize
End If
```

Only the name and the size are used: the bold and italic styles of the requester
(`FontBold`, `FontItalic`) don't change a window's font. Keep the choice in the program's
settings and set it again in `Form_Load`. The text editor control also has `FixedFont`, which
switches it to the user's fixed-width font.

## Started from Workbench or from the Shell

An AmigaOS program can be started in two ways, and a good program works with both:

- **From the Shell**, with arguments on the command line: `Jotter Work:Notes/todo.txt`.
- **From Workbench**, by double-clicking its icon, or by double-clicking a document's
  (project) icon whose default tool is the program, or by selecting a few icons with Shift held
  and double-clicking the program's icon last.

These tell you how the program was started and what it was given:

| | What it is |
|---|---|
| `App.FromWorkbench` | `True` if the program was started by double-clicking its icon (or a project icon). Programs started with `WBRun` or by other programs through Workbench get a CLI and see `False` |
| `App.ArgCount` | the number of files the program was given: the project icons from Workbench, or the words of the command line |
| `App.Arg(i)` | file `i` (from 0) with its full path when it came from Workbench |
| `Command` | the whole command line as one string (empty from Workbench) |
| `App.ToolType(name [, default])` | a tooltype of the program's icon (next section) |
| `App.ReadArgs(template)`, `App.ArgValue(key)` | the arguments read with an AmigaDOS template, or from the tooltypes when started from Workbench ([below](#arguments-templates-and-tooltypes)) |
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
    On Error Resume Next                             ' fails if a Jotter is running already
    App.HotKey "popup", "ctrl alt j"                 ' brings Jotter to the front; an Exchange entry
    On Error GoTo 0
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
- **Interpreted programs.** A program that runs in the interpreter starts from Workbench too:
  give its `.bas` or `.bbp` file a project icon whose default tool is `boing` (see
  [Interpreted programs from Workbench](#interpreted-programs-from-workbench)). A native build
  (`boing build`) is still the better choice for programs you give to other people.
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

### Arguments: templates and tooltypes

AmigaOS commands describe their arguments with a **template**, such as
`FILE/A,SIZE/N,QUIET/S` (type a system command followed by `?` in the Shell to see its own).
`App.ReadArgs(template)` reads the program's arguments with such a template, the way the
system's own commands do, and returns `True` (a Boolean) if they fit it. `App.ArgValue(key)`
then gives each value:

| Template item | Means | `App.ArgValue` gives |
|---|---|---|
| `FILE` | an argument, by position or as `FILE name` / `FILE=name` | the text, `""` if it was not given |
| `FILE/A` | the argument must be given | the text |
| `FROM/K` | it must be given with its keyword: `FROM Work:x` | the text |
| `SIZE/N` | a whole number | the number as text (`Val` it) |
| `QUIET/S` | a switch: just the word | `"1"` if it was given, else `""` |
| `FAST/T` | a toggle: the keyword with `ON` or `OFF` (or `YES` or `NO`): `FAST=ON` | `"1"` or `"0"` (`"0"` also when it was not given) |
| `FILES/M` | any number of values | all of them, joined by `vbLf` (`Split(v, vbLf)`) |
| `NUMS/N/M` | any number of whole numbers | the numbers as text, joined by `vbLf` |
| `TEXT/F` | the rest of the line, spaces and all | the text |
| `F=FILE` | `F` is a short name for `FILE` | `App.ArgValue("FILE")` |

Keywords are not case-sensitive: the user can type `quiet` or `size=5`. `ReadArgs` returns
`False` when the arguments don't fit (a missing `/A` argument, a word that isn't a number for a
`/N`, an unknown keyword); the program then prints its template as a usage line. `ArgValue`
with a key that isn't in the template (or before `ReadArgs`) is error 5. A template has up to
32 items: a longer one is error 5. `App.ReadArgs` and `App.ArgValue` work only on AmigaOS: on
other systems they are error 438.

**Started from Workbench**, a program has no command line, and `ReadArgs` reads the icon's
tooltypes instead: the tooltype `MINUTES=5` is the value of the template's `MINUTES`, a bare
`REPEAT` gives `"1"`, and a `/T` item's tooltype `FAST=ON` gives `"1"` (`OFF`, `NO` or `0` give
`"0"`; without the tooltype, `""`). The template is checked here too: `ReadArgs` returns `False`
when an `/A` item has no tooltype, or the tooltype of an `/N` item isn't a whole number. So one
template covers both ways of starting the program; only the way of telling the user differs,
as there is no Shell to print a usage line to.

Here is the start of **Reminder**, a program without a window from
`examples/book/ch18-desktop/reminder/`, which shows a notification after some minutes.
In the Shell it is started as `Reminder "Tea is ready" 5` (or `Reminder TEXT="Tea is ready"
MINUTES=5 REPEAT`); from Workbench, its icon's tooltypes are `TEXT=Tea is ready` and
`MINUTES=5`. When they don't fit the template, it prints its usage in the Shell and opens a
requester from Workbench:

*Listing 18.3* (`examples/book/ch18-desktop/reminder/Reminder.bbp`)

<!-- project: examples/book/ch18-desktop/reminder/Reminder.bbp -->
```basic
Public Sub Main()
    If Not App.ReadArgs("TEXT/A,MINUTES/N,REPEAT/S") Then
        If App.FromWorkbench Then                       ' no Shell to print to
            App.Request "Reminder's icon needs the tooltype TEXT=..." & vbLf & _
                        "(and MINUTES=, if given, a whole number).", "_OK", "Reminder", vbExclamation
        Else
            Print "Usage: Reminder TEXT/A,MINUTES/N,REPEAT/S"
        End If
        Exit Sub
    End If
    message = App.ArgValue("TEXT")
    minutes = Val(App.ArgValue("MINUTES"))
    If minutes <= 0 Then minutes = 10
```

`Command` and `App.Arg(i)` still give the raw command line and the files, for programs that
want them as they are.

### Interpreted programs from Workbench

A program that runs in the interpreter is a `.bas` or `.bbp` file (or a compiled `.bbc`), not
an executable. To start it from Workbench, give that file a project icon whose **default tool**
is `boing`, for example `BOING:boing`: double-clicking the icon then runs the program as
`boing run` would. `boing` asks for a stack of 1 MB itself, which is plenty for windows.

You can make such an icon in Workbench (copy a project icon, then set its default tool in the
Information window), or let Boing BASIC write it: `App.SaveIcon path, "BOING:boing"` writes
`path.info` with that default tool. This small program, run once, gives Jotter's project file
its icon:

*Listing 18.4* (`examples/book/ch18-desktop/listing-18-04.bas`)

```basic
' an icon for Jotter.bbp: double-clicking it runs Jotter in the interpreter
App.SaveIcon "Work:Projects/Jotter/Jotter.bbp", "BOING:boing"
```

Things to know about a program started this way:

- **The console.** The program gets a console window, but only when it prints something: a
  program with windows that never uses `Print` doesn't get one. `Input` reads from the same
  window. At the end the window stays open until the user closes it, so the output can be read.
  A compile error appears there too.
- **How it was started.** The program sees the project as itself: `App.FromWorkbench` is
  `True` and `Command` is `""`. `App.ToolType` and `ReadArgs` read the tooltypes of the project
  icon that started it: put them into `Jotter.bbp.info` (or `Jotter.bas.info`), the icon you
  double-click.
- **Other icons.** Icons selected together with the project (click the project's icon, then
  Shift-click the others and double-click the last one with Shift held) are the program's
  files: `App.ArgCount` counts them, and `App.Arg(0)`, `App.Arg(1)`... give their full paths.
  The project itself is not one of them.
- Only give program files `boing` as their default tool. A document saved by a program running
  in the interpreter needs a default tool that opens it: the program's native build
  (`App.SaveIcon fileName, "Work:Jotter/Jotter"`), or a script.

An older way, which still works, is a small script whose icon has the default tool `C:IconX`.
The program then sees itself as started from the Shell (`App.FromWorkbench` is `False`), and
the script can pass arguments and set the stack:

```sh
; Jotter-run: start Jotter in the interpreter (icon default tool: C:IconX)
Stack 262144
boing run Work:Projects/Jotter/Jotter.bbp
```

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

*Listing 18.5* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

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
explicitly there: `App.SaveIcon fileName, "Work:Jotter/Jotter"` (see
[Interpreted programs from Workbench](#interpreted-programs-from-workbench)).

## Workbench integration

### AppWindows: files dropped on a window

With `dropfiles=1` on the `window` line, the form is an **AppWindow**: the user can drag icons
from Workbench and drop them on it. The form's `Form_OLEDragDrop(Count As Integer, X As Integer,
Y As Integer)` runs with the number of icons and the drop position inside the window, and
`App.DropFile(i)` (from 0 to `Count - 1`) is each file's full path. `dropfiles=1` on a single
control makes drops over that control call `<id>_OLEDragDrop` instead, with X and Y inside the
control. `Me.OLEDropMode = 1` turns the AppWindow on from code.

Dragging works in one direction only. AmigaOS 4 has no drag-and-drop protocol between
programs: icons can be dropped *onto* an AppWindow or an AppIcon, but nothing can be dragged
*out of* a program's window to the Workbench or to another program. This is a limit of the
system, not of Boing BASIC. Give the user the data another way: through the clipboard
(`Clipboard.SetText`, `Clipboard.SetPicture`), or by saving a file with an icon
(`App.SaveIcon`), which can then be dragged from its drawer. Dragging inside a window works as
usual: reordering the lines of a list or tree view, or dragging on a canvas with its
`MouseDown` and `MouseMove` events.

*Listing 18.6* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

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

*Listing 18.7* (`examples/book/ch18-desktop/listing-18-07.bas`)

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
| `ShowPalette` | a palette requester: edits up to 256 colours (`Colors(i)`, `ColorCount`) and picks one (`ColorIndex`) |
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

*Listing 18.8* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

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
  bar: not every user knows that Shift or Ctrl with the right button opens a context menu, and
  the menus show the shortcuts.

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

On the Amiga the right mouse button is the menu button: hold it down anywhere in the window to
see the menu bar. Boing BASIC keeps it that way, also over controls that have a context menu.
A control can have a **context menu**, a pop-up menu of what can be done with it
(`contextmenu=mnuEdCtx` names a hidden top-level `menu`; see
[chapter 13](13-menus-dialogs.md#context-menus)). It opens when the user holds **Shift or Ctrl**
and presses the right button over the control. Jotter's text area has one with Cut, Copy and
Paste:

```text
  texteditor id=ed contextmenu=mnuEdCtx
...
menu id=mnuEdCtx text="Edit" hidden=1
  menu id=mnuCtxCut text="Cut"
  menu id=mnuCtxCopy text="Copy"
  menu id=mnuCtxPaste text="Paste"
```

`contextmenukey=always` on the `window` line (or `Me.ContextMenuKey = 0` in code) makes the
context menus open with a plain right click, as in some other systems; the menu bar can then
only be reached where no control has a context menu. Leave it at the default unless the
window has no menu bar. Mention the Shift-click in your help, and put the context menu's
commands in the menu bar too.

In a paint program or a game the right button may be needed for drawing: `rmb=1` on a canvas
sends the right button to the canvas (as a `MouseDown` with button 2), with or without Shift or
Ctrl, while the pointer is over it; the menus still work everywhere else in the window.

## Keyboard control

An AmigaOS program can be used without the mouse as far as possible:

- **Shortcut letters.** A `_` in a control's text or in its `label=` underlines the next
  letter, and that letter is the control's keyboard shortcut: `text="_Save"` shows **S**ave
  with the S underlined, and pressing S clicks the button. The key works on its own or with
  Shift; combinations with an Amiga key or Ctrl are left to the menus and the program. Use a
  different letter for each control of the window. What the key does depends on the control:

  | Control | Its letter comes from | The shortcut key |
  |---|---|---|
  | button | `text=` (or `label=`) | clicks it (its `Click` event runs) |
  | check box | `text=` (or `label=`) | ticks or clears it (`Click` runs) |
  | text field, number field, text editor | `label=` only | puts the cursor into it |
  | chooser, radio buttons, tabs, list | `text=` (or `label=`) | selects the next item, or with Shift the previous one, going round at the end (`Click` runs) |
  | label (`label text="_Port"`) | `text=` | works the next control after it in the `.afg` (a field, button, check box, chooser, radio buttons or list) as that control's own letter would: `label text="_Port"` followed by `integer id=port` puts the cursor into the number field |

  A field's text is what the user types, so a `_` in it is just a character. Other controls
  (sliders, scrollers, file choosers, tree views, grids...) have no shortcut, and a `_` in their `label=` doesn't
  take a letter away from the others.

- **Return and Esc.** `default=1` on a button makes Return click it, `cancel=1` on a button
  makes Esc click it. Give a dialog an OK (or Save) button with `default=1` and a Cancel
  button with `cancel=1`.
- **Tab** moves from one text or number field to the next (and Shift-Tab back). While a text
  field has the cursor it takes the typing, the shortcut letters included. A text field reports
  Return and Tab in its `KeyPress` event, so Return in a field can start the action
  (`If KeyAscii = 13 Then ...`).
- **Help** opens the program's help (see [Help](#help-amigaguide)).
- `SetFocus` puts the cursor into a text field, for example the first field when a dialog
  opens.

The settings window of the [layout example](#windows-that-fit-any-font-and-screen) needs no
code for its keyboard: its `.afg` gives every control a letter, and its buttons are

```text
  hlayout even=1 weight=0
    button id=save text="_Save" default=1 hint="Use the settings and keep them after a reboot"
    space
    button id=use text="_Use" hint="Use the settings until the next reboot"
    space
    button id=cancel text="_Cancel" cancel=1 hint="Close without changing anything"
```

so M and E put the cursor into the message and minutes fields, F switches the check box, O
chooses the next sound, S or Return saves, U uses, and C or Esc cancels.

A key that a control takes as its shortcut (or Return and Esc for a `default=1` or `cancel=1`
button, or Help when it opens the help) does not also arrive in `Form_KeyDown`,
`Form_KeyPress` or `Form_KeyUp`: the window gets neither its press nor its release. Keys
without a control arrive there as usual ([Forms and controls](12-forms.md#the-keyboard)).

## Window titles, the busy pointer and hints

- **The window title** names the program and the document: `Jotter: todo.txt`. Mark unsaved
  changes, for example with a `*`, and change the title when the document changes:

*Listing 18.9* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

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
- **A help line in the status bar.** Many Amiga programs say in a line at the bottom of the
  window what the control under the pointer does. A `statusbar` with `hints=1` does that with
  the same `hint=` texts: while the pointer is over a control with a hint, the status bar's
  first panel shows it, and when the pointer leaves, the panel shows your own text again. The
  hint is the help bubble as well, so one text serves both:

  ```text
  statusbar id=sb panels="Ready|Ln 1" widths="0|60" hints=1
  ```

## An ARexx port

ARexx is the Amiga's scripting language, and a program with an **ARexx port** can be driven by
scripts and by other programs. Give every program with documents a port, named after the
program in capitals. Setting `App.ARexxPort` opens it (if the name is taken, because the
program runs twice, it becomes `JOTTER.1` and so on: `App.ARexxPortName` is the name actually
used, worth showing in the About requester). Each command that arrives calls
`ARexx_Command(Cmd As String, Args As String, Result As String)`, with the first word in `Cmd`
and the rest of the line in `Args`:

*Listing 18.10* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

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

*Listing 18.11* (`examples/book/ch18-desktop/listing-18-11.bas`)

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

## Notifications

A **notification** is a small message that appears for a few seconds in a corner of the screen
and then goes away by itself; AmigaOS 4 shows them with **Ringhio**. Use one for news that
needn't stop the user: a download has finished, a reminder is due, a job in the background
failed. A requester would make the user click; a notification doesn't.

| | What it does |
|---|---|
| `App.Notify title, text [, imagefile]` | shows a notification with a title and a text, and the picture `imagefile` (a picture file such as a PNG) if given. The image's path is read like the program's other file paths, so `App.Path & "/bell.png"` works when the program is at the top of a volume ([Files beside the program](10-files.md#files-beside-the-program-apppath)). The program goes on at once. Error 5 if it can't be shown |
| `App.NotifyResult` | the last answer of application.library to `Notify` (0 = queued), for finding out why one failed |
| `App.Register` | registers the program with application.library without a notification; `True` if it worked (see [below](#quit-hide-and-show-from-the-system)) |

Notifications go through **application.library**: the first `App.Notify` registers the program
there under its `App.Title`, so set the title first if the program changes it. Ringhio's
preferences decide where the message appears and for how long. If the notification server
isn't running, `Notify` is error 5: a program that must tell the user something can catch the
error and open a requester instead, as Reminder does:

*Listing 18.12* (`examples/book/ch18-desktop/reminder/Reminder.bbp`)

<!-- project: examples/book/ch18-desktop/reminder/Reminder.bbp -->
```basic
' a notification; a requester if notifications don't work (no Ringhio server running)
Private Sub Tell(ByVal text As String)
    On Error GoTo noRinghio
    App.Notify "Reminder", text
    Exit Sub
noRinghio:
    App.Request text, "_OK", "Reminder", vbInformation
End Sub
```

Keep the text short: one or two lines that make sense on their own. Programs that call
application.library themselves (see [Calling AmigaOS](17-amigaos.md)) find its tags, such as
`APPNOTIFY_Title` and `REGAPP_Description`, in `BOING:bindings/application.bi`.

## Commodities: a hotkey and Exchange

**Commodities** are the AmigaOS programs that work in the background and react to the input of
every program: a key combination that pops up a window, a screen blanker. The system's
**Exchange** program lists them, with buttons to show, hide or remove each one. A Boing BASIC
program becomes a commodity when it asks for a hotkey:

| | What it does |
|---|---|
| `App.HotKey name, keys` | from now on, pressing `keys` anywhere calls `HotKey_Pressed` with `name`. `keys` is a commodities description: `"ctrl alt j"`, `"lcommand f1"`, `"shift help"` |
| `HotKey_Pressed(Name As String)` | a Sub you write, in any module: the hotkey `Name` was pressed |

The key description is the system's: the qualifiers `ctrl`, `shift` (`lshift`, `rshift`),
`alt` (`lalt`, `ralt`), `lcommand` and `rcommand` (the Amiga keys), followed by a key: a letter
or digit, `f1` to `f10`, `help`, `esc`, `space`, `return`, `tab`, `up`, `down`... The keys of a
hotkey are taken: the active window doesn't get them, so choose a combination other programs
are unlikely to use, and let the user change it (in a tooltype or a setting). A description
commodities can't read is error 380; up to 32 hotkeys can be given (error 7 after that).

The first hotkey also gives the program its entry in Exchange, named after `App.Title`. Its
buttons call Subs of your program:

| Exchange | Calls |
|---|---|
| **Show** | `App_Show()`: open the window and bring it to the front |
| **Hide** | `App_Hide()`: hide (iconify) the window |
| **Remove** | `App_Quit()`: quit (ask first if there is unsaved work) |
| **Active** / **Inactive** | switches the hotkeys on and off (Boing BASIC does this itself) |

The name in Exchange can be used by only one program at a time. When a second copy of the
program asks for a hotkey, it gets error 5, and the copy that is already running gets an
`App_Show` call instead: a simple way to bring the first copy to the front. The hotkeys and the
Exchange entry are removed when the program ends.

Jotter asks for **Ctrl-Alt-J**, which brings its window to the front from anywhere, and answers
Exchange's buttons:

*Listing 18.13* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub PopUp()
    Me.WindowState = 0                               ' open the window again if it is iconified
    Me.SetFocus                                      ' to the front, and active
End Sub

Private Sub HotKey_Pressed(Name As String)
    If Name = "popup" Then PopUp
End Sub

Private Sub App_Show()                               ' Exchange's Show, or a second Jotter started
    PopUp
End Sub

Private Sub App_Hide()                               ' Exchange's Hide: iconify
    Me.WindowState = 1
End Sub

Private Sub App_Quit()                               ' Exchange's Remove: like Quit, it asks first
    PopUp
    Unload Me
End Sub
```

The hotkey itself is asked for in `Form_Load` ([Listing 18.1](#started-from-workbench-or-from-the-shell)),
with `On Error Resume Next`, because it fails when Jotter is running already.

A program with windows gets its hotkeys while its event loop runs; a program without windows
gets them when it calls `DoEvents`, as Reminder does in its main loop. Reminder's
**Ctrl-Alt-R** shows how long is left:

*Listing 18.14* (`examples/book/ch18-desktop/reminder/Reminder.bbp`)

<!-- project: examples/book/ch18-desktop/reminder/Reminder.bbp -->
```basic
' Ctrl-Alt-R, from any program
Sub HotKey_Pressed(Name As String)
    If Name = "left" Then Tell CLng((dueAt - elapsed) / 60) & " minutes left: " & message
End Sub

' Exchange's Remove, or a Quit sent through application.library
Sub App_Quit()
    quitting = True
End Sub
```

`App.HotKey` works only on AmigaOS: on other systems it is error 438.

### Quit, Hide and Show from the system

`App_Quit`, `App_Hide` and `App_Show` are called for Exchange's buttons, and also when another
program sends the program a quit, hide or show message through application.library, which it
can do once the program is registered there (after its first `App.Notify`, or after
`App.Register`). Like the other event Subs, they can be in any module and are called while the
event loop runs or `DoEvents` is called.

Without an `App_Quit` Sub, a Quit (or Exchange's Remove) closes the program's windows the way
their close gadgets do: every loaded form gets `Form_QueryUnload`, with `UnloadMode` 3
(`vbAppTaskManager`), and then `Form_Unload`. A form whose `Form_QueryUnload` sets
`Cancel = True` stays open, and so does the program; when the last form is unloaded, the
program ends as usual. A program without forms ends at once, as if it had reached `End`.

`Form_QueryUnload` can tell a request from the system by its `UnloadMode`:

| `UnloadMode` | Constant | The form is closed by |
|---|---|---|
| 0 | `vbFormControlMenu` | the window's close gadget |
| 1 | `vbFormCode` | `Unload` in the program's code |
| 3 | `vbAppTaskManager` | the system: Exchange's Remove, or a Quit through application.library |

Still, write an `App_Quit` whenever your program has a hotkey or registers: it decides what
quitting means. In `App_Quit`, do what the program's own Quit does: `Unload` the main window
(which asks about unsaved changes, and may be cancelled), or set the flag that ends the main
loop, as Reminder does. A program without forms that has work to finish needs one, because
without it the program ends where it stands.

## Settings in ENV: and ENVARC:

AmigaOS keeps programs' settings as small files in two places: `ENVARC:` on disk, which survives
a reboot, and `ENV:`, a copy in RAM that programs read. `SaveSetting app, section, key, value`
writes `ENVARC:app/section/key` and `ENV:app/section/key`, and
`GetSetting(app, section, key [, default])` reads `ENV:` first, then `ENVARC:`, then returns the
default. `DeleteSetting app, section [, key]` removes a setting or a whole section. Use the
program's name as `app`: the user then finds every setting in `ENVARC:Jotter/` (and `remember=1`
windows keep their place in the same drawer). More in [Files and the system](10-files.md).

*Listing 18.15* (`examples/book/ch18-desktop/listing-18-15.bas`)

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
**Cancel**. Each has its statement:

| Button | What to do |
|---|---|
| **Save** | `SaveSetting app, section, key, value`: writes `ENV:` and `ENVARC:`, so the setting is used now and kept after a reboot |
| **Use** | `UseSetting app, section, key, value`: writes `ENV:` only, so the setting is used now and forgotten at the next reboot (the copy in `ENVARC:`, if there is one, comes back then) |
| **Cancel** | nothing: close the window |

`GetSetting` reads `ENV:` first, so a program that reads its settings finds a used setting as
well as a saved one. The settings editor of the [layout example](#windows-that-fit-any-font-and-screen)
does exactly this:

*Listing 18.16* (`examples/book/ch18-desktop/prefs/Prefs.bbp`)

<!-- project: examples/book/ch18-desktop/prefs/Prefs.bbp -->
```basic
Private Sub save_Click()
    SaveSetting APPNAME, "Alarm", "Message", message.Text
    SaveSetting APPNAME, "Alarm", "Minutes", CStr(minutes.Value)
    SaveSetting APPNAME, "Sound", "Flash", CStr(flash.Value)
    SaveSetting APPNAME, "Sound", "Sound", CStr(sound.ListIndex)
    Unload Me
End Sub

' Use: only ENV: (gone after a reboot); GetSetting reads ENV: first
Private Sub use_Click()
    UseSetting APPNAME, "Alarm", "Message", message.Text
    UseSetting APPNAME, "Alarm", "Minutes", CStr(minutes.Value)
    UseSetting APPNAME, "Sound", "Flash", CStr(flash.Value)
    UseSetting APPNAME, "Sound", "Sound", CStr(sound.ListIndex)
    Unload Me
End Sub
```

`DeleteSetting` removes a setting from both places. On a host, where there is no `ENV:`, both
statements write to the same settings directory ([Files and the system](10-files.md#settings-savesetting-and-getsetting)).

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
| `Clipboard.HasText` | `True` if there is text on the clipboard |
| `Clipboard.GetFormat(format)` | `True` if the clipboard holds that kind of data: `vbCFText` for text, `vbCFBitmap` or `vbCFDIB` for a picture (other formats: `False`) |
| `Clipboard.Unit` | the clipboard unit all the members above use: 0 (the shared clipboard, at first) to 255 |

Offer the clipboard through the Edit menu with the standard keys (Amiga-X, -C, -V), and grey
out Paste when there is nothing to paste: check `Clipboard.HasText` (or `GetFormat`) when the
window becomes active, since another program may have changed the clipboard meanwhile.

AmigaOS has 256 clipboard **units**. Unit 0 is the clipboard of the desktop, the one users
mean when they copy and paste. The others are for programs: a second clipboard that the user's
copying doesn't overwrite (some editors offer several), or a place where two programs of yours
exchange data. `Clipboard.Unit = 2` makes every `Clipboard` call use unit 2, until you set it
back to 0. Text on other units is stored as IFF FTXT, the clipboard's standard text format, and
pictures as IFF ILBM, as on unit 0, so other programs that know the unit can read them:

*Listing 18.17* (`examples/book/ch18-desktop/listing-18-17.bas`)

<!-- run -->
```basic
' A second clipboard: unit 1 keeps its text while the user copies other things
Option Explicit
Dim kept As String

Clipboard.SetText "the user's text"
Clipboard.Unit = 1
Clipboard.SetText "a signature"
Clipboard.Unit = 0
Print Clipboard.GetText()

Clipboard.Unit = 1
If Clipboard.GetFormat(vbCFText) Then kept = Clipboard.GetText()
Clipboard.Unit = 0
Print kept
```

```output
the user's text
a signature
```

On a host, each unit is a clipboard of the program's own, which other programs don't see.

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

*Listing 18.18* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

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

(The form is called `editor` here, though `jotter`, the name of its own file, would do as
well. What it can't be called is the name of another module, a class or a Public procedure or
variable, such as `Main` or `Startup`: that is a compile error.)

In code, translate every text the user sees, and build sentences with placeholders rather than
by joining pieces, because the word order differs between languages:

*Listing 18.19* (`examples/book/ch18-desktop/listing-18-19.bas`)

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

## Number and date formats

The Locale preferences also say how the user writes numbers and dates: a decimal comma in
Germany (`1.234,50`), a decimal point in Britain (`1,234.50`), the day before the month or
after it. `Format` and the date functions always write them one way (see
[Built-in functions](09-builtins.md#format)), which suits files and fixed layouts. For numbers
and dates that the user reads, use the App object's locale functions instead:

| | |
|---|---|
| `App.FormatNumber(x [, decimals])` | `x` with the user's decimal point and thousands separator, and `decimals` digits after the point (2 if not given; 0 to 10) |
| `App.FormatDate(d [, format])` | the date (and time) `d` in the user's format: `"short"` (the default), `"long"`, `"time"` or `"datetime"`, or a pattern of your own (below) |
| `App.DecimalPoint` | the user's decimal point, as a string (`"."` or `","`) |
| `App.GroupSeparator` | the user's thousands separator, as a string (may be `""`) |

*Listing 18.20* (`examples/book/ch18-desktop/listing-18-20.bas`)

<!-- run -->
```basic
' Numbers in the user's own format; on a host: "." and ","
Option Explicit
Print App.FormatNumber(1234567.891)
Print App.FormatNumber(-42.5, 1)
Print App.FormatNumber(1999, 0)
Print "Point "; App.DecimalPoint; ", separator "; App.GroupSeparator
```

```output
1,234,567.89
-42.5
1,999
Point ., separator ,
```

With German Locale settings, the same program prints `1.234.567,89`, `-42,5` and `1.999`.

`App.FormatDate`'s own patterns are those of AmigaOS's locale.library, made of `%` codes; the
names of days and months are in the user's language:

| Code | Meaning | Code | Meaning |
|---|---|---|---|
| `%d`, `%-d` | day of the month, `09` / `9` | `%e` | day of the month with a leading space, ` 9` |
| `%m`, `%-m` | month, `03` / `3` | `%b`, `%B` | month name, short and long |
| `%y`, `%Y` | year, `24` / `2024` | `%a`, `%A` | day name, short and long |
| `%H`, `%M`, `%S` | hour (24-hour clock), minute, second | `%I`, `%p` | hour (12-hour clock), AM or PM |
| `%F` | `%Y-%m-%d` | `%T` | `%H:%M:%S` |
| `%j` | day of the year, `069` | `%%` | a `%` |

A `-` after the `%` leaves out the leading zero, as in `%-d`. The four named formats come from
the user's Locale settings; the `%` codes are the same for everyone (only the names change
language), so use a named format unless the layout really must be fixed.

*Listing 18.21* (`examples/book/ch18-desktop/listing-18-21.bas`)

```basic
' Today's date as the user likes it
Option Explicit
Dim d As Date
d = Now
Print App.FormatDate(d)                   ' the short date, in the user's order
Print App.FormatDate(d, "long")           ' the long date, with names
Print App.FormatDate(d, "time")           ' the time
Print App.FormatDate(d, "datetime")       ' both
Print App.FormatDate(d, "%A %-d %B")      ' for example: Tuesday 10 November
Print App.FormatDate(d, "%Y-%m-%d")       ' for example: 2026-11-10
```

On a host, without locale.library, `App.FormatDate` gives the same text as `CStr(d)` whatever
the format. Keep `Format` for what a program writes into files: a number written with the
user's decimal comma can't be read back with `Val`.

## Help: AmigaGuide

AmigaOS help files are AmigaGuide documents (`.guide`), shown by the system's help viewer with
links between nodes. Every program with a window should have one, opened by the **Help** key
and by a Help item in the Project menu:

- `App.HelpFile = App.Path & "/Jotter.guide"` makes the Help key open that file at its `main`
  node, from any of the program's windows.
- `App.ShowHelp file [, node]` opens the help at a node, for a Help menu item or a "?" button.
  The help opens in its own window; the program keeps running.
- **Help for the control under the pointer.** `helpnode=` on a control in the `.afg` (the
  `HelpNode` property at run time) names the node the Help key opens while the pointer is over
  that control; `helpnode=` on the `window` line is the node for the rest of the window. Without
  either, Help opens `main`. This is the context-sensitive help Amiga users expect: point at a
  field, press Help, read about that field.
- Without `App.HelpFile`, the Help key arrives in `Form_KeyDown` as `vbKeyHelp`, so a program
  can do something of its own with it (a game can show its keys).

*Listing 18.22* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub mnuHelp_Click(): App.ShowHelp App.HelpFile, "main": End Sub
```

Give the guide a node for each window or area of the program (named on its `window` line),
nodes for the controls that need explaining, and a node listing the ARexx commands:

```text
window name=prefs title="Alarm preferences" helpnode=prefs
vlayout id=root
  vlayout title="Alarm"
    string id=message label="_Message" helpnode=message hint="The text the alarm shows"
```

## Version strings

The AmigaOS `Version` command, Workbench's information window and installers find a program's
version in its file: a text `$VER: name version.revision (dd.mm.yyyy)`. Give the project a
`Title=` and a `Version=` line, and `boing build` puts that text into the native program for
you, with the date of the build:

```ini
Name=Jotter
Title=Jotter
Version=1.0
```

`Version Jotter` in a Shell then prints `Jotter 1.0`. The program can read the same numbers as
`App.Major`, `App.Minor` and `App.Revision`, and the title as `App.Title`:

*Listing 18.23* (`examples/book/ch18-desktop/listing-18-23.bas`)

<!-- run -->
```basic
Print "Version"; App.Major; "."; App.Minor
App.Title = "Jotter"
Print App.Title
```

```output
Version 0 . 0 
Jotter
```

(Run as a single file it has no project, so its version is 0.0 and its title is the file's
name until the program sets one.)
An About requester usually shows both. Jotter keeps its own `$VER:` text in a constant as well,
which works in the interpreter too:

Raise the version when you release a new one, and write the date as day, month and year with
dots. Jotter shows it in its About requester:

*Listing 18.24* (`examples/book/ch18-desktop/jotter/Jotter.bbp`)

<!-- project: examples/book/ch18-desktop/jotter/Jotter.bbp -->
```basic
Private Sub mnuAbout_Click()
    App.Request Mid(VERSTAG, 7) & vbLf & "A small text editor." & vbLf & _
                "ARexx port: " & App.ARexxPortName, "_OK", "About " & APPNAME, vbInformation
End Sub
```

## Games on the desktop

A game can run in a window on the Workbench, among the user's other programs, or on a screen
of its own. A game in a window shares the screen with other programs, and should behave like
one:

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

*Listing 18.25* (`examples/book/ch18-desktop/game/Game.bbp`)

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

### A full-screen game on its own screen

A game that wants the whole display opens a screen of its own and covers it with a
`fullscreen=1` window. Here is the same game as above, from
`examples/book/ch18-desktop/fullscreen/`. Its `window` line asks for its own 800 x 600 screen:

```text
# fullgame.afg - the game window covers its screen: the program's own 800 x 600 screen,
# unless Sub Main has opened one in the mode the user chose
window name=play title="Boing Catch" screen=own screenwidth=800 screenheight=600 fullscreen=1
vlayout id=root
  canvas id=view width=320 height=200 scale=2
  timer id=tick interval=20
```

The window is as big as the screen, and the 640 x 400 picture is centred in it. The screen
must be a little larger than the picture, because the layout keeps a small margin around its
controls: a window whose layout needs more room than the screen has can't open (error 7).

The program starts in `Sub Main`, which lets the user choose a screen mode first (and
remembers it). If the user chooses one that is big enough, `App.OpenScreen` opens the screen in
that mode before the form is loaded, so the form opens there; otherwise the form's
`screen=own` opens the 800 x 600 screen:

*Listing 18.26* (`examples/book/ch18-desktop/fullscreen/FullScreen.bbp`)

<!-- project: examples/book/ch18-desktop/fullscreen/FullScreen.bbp -->
```basic
' Startup.bas - asks for a screen mode, opens the game's own screen and plays on it
Option Explicit

Public Const APPNAME = "BoingCatch"

Public Sub Main()
    Dim dlg As Object
    Set dlg = CreateObject("Boing.CommonDialog")
    dlg.DialogTitle = "Boing Catch: choose a screen mode"
    dlg.ScreenModeID = CLng(GetSetting(APPNAME, "Screen", "Mode", "0"))
    dlg.ShowScreenMode
    If Not dlg.Cancelled Then
        ' the 640 x 400 picture and the layout's margin need a bit more than 640 x 400
        If dlg.ScreenWidth < 680 Or dlg.ScreenHeight < 440 Then
            MsgBox "That mode is too small: the game uses 800 x 600.", vbInformation, "Boing Catch"
        Else
            SaveSetting APPNAME, "Screen", "Mode", CStr(dlg.ScreenModeID)
            On Error GoTo noScreen
            App.OpenScreen dlg.ScreenModeID, dlg.ScreenWidth, dlg.ScreenHeight, dlg.ScreenDepth, "Boing Catch"
            On Error GoTo 0
        End If
    End If
start:
    ' loaded now, so it opens on that screen; without one, its screen=own opens 800 x 600
    play.Show vbModal
    Exit Sub
noScreen:
    MsgBox "Can't open that screen mode." & vbLf & "The game uses 800 x 600.", vbExclamation, "Boing Catch"
    Resume start
End Sub
```

A full-screen window has no close gadget and no iconify gadget, so the keys matter more than
in a window: Esc asks before quitting, P pauses, Help shows the keys, and the game pauses
when it loses the input (`Form_Deactivate`), for example when the user switches to another
screen with Left-Amiga M. `MsgBox` and the other requesters open on the game's screen. The
screen closes when the program ends.

Things to know about screens of your own:

- The screen is like the Workbench (its mode, depth and font) in everything you don't give.
  It is a public screen named after the program, so other programs could open windows on it
  too; `App.CloseScreen` returns `False` while any window is still open there.
- The `fullscreen=1` window hides the screen's title bar, whether `App.OpenScreen` or the
  `.afg`'s `screen=own` opened the screen, so the whole screen is the game's.
- A game that runs on its own screen should still offer a window on the Workbench for users who
  prefer it: a tooltype or a setting that chooses between two forms, one with `screen=own
  fullscreen=1` and one without.

> **Not yet supported**
>
> These AmigaOS features have no Boing BASIC support yet (some can be reached with `Declare`,
> see [Calling AmigaOS](17-amigaos.md)):
>
> - Choosing the public screen at run time (for example from a `PUBSCREEN` tooltype): `pubscreen=` is fixed in the `.afg`, and there is no property for it.
> - Screens with their own palette or pens.
> - Bold and italic window fonts: `Me.FontName` and `Me.FontSize` take only the name and size of a `ShowFont` result.
> - application.library beyond notifications and the Quit, Hide and Show messages (for example its list of recently used documents), and notifications with buttons.
> - Commodities other than hotkeys (filtering or changing the input of other programs).
> - Clipboard data other than text and pictures (`Clipboard.GetFormat` answers `False` for any other format).

## Summary

- Lay windows out in groups with weights, never at fixed pixels, so they fit any font and
  screen; offer resizing, iconifying and remembered positions. Leave fonts to the user unless
  there is a reason (`font=`, `Me.FontName` after `ShowFont`).
- Windows open on the default public screen; `pubscreen=` names another one, and `screen=own`
  or `App.OpenScreen` (with a `ShowScreenMode` result) opens the program's own screen, which a
  `fullscreen=1` game window can cover.
- Accept files from Workbench and the Shell (`App.Arg`), read tooltypes with defaults, take
  options with an AmigaDOS template (`App.ReadArgs`, `App.ArgValue`; tooltypes from Workbench),
  and give saved documents icons with `App.SaveIcon`.
- A project icon with the default tool `boing` starts an interpreted program from Workbench,
  with a console window that opens when it prints; its tooltypes are the program's, and icons
  selected with it are `App.Arg(i)`.
- Use the ASL requesters (and `ShowPalette` for a palette), ask before discarding work, and
  name requester buttons after what they do.
- Files can be dropped onto a program, but AmigaOS has no way to drag data out of one: offer
  the clipboard (unit 0, or a unit of your own with `Clipboard.Unit`) or a saved file instead.
- Project, Edit, Settings menus with the standard Amiga-key shortcuts; Quit last; `...` on items
  that open a requester; `_` shortcut letters, `default=1` and `cancel=1` buttons and Help for
  the keyboard; the right button shows the menu bar, Shift or Ctrl + right button a context
  menu. `hint=` texts are help bubbles, and with `statusbar hints=1` a help line too.
- `App.Notify` shows a Ringhio notification. `App.HotKey` gives a hotkey (`HotKey_Pressed`) and
  an Exchange entry; `App_Show`, `App_Hide` and `App_Quit` answer Exchange and application.library,
  and every program with a hotkey should have an `App_Quit` (without one, a Quit closes the
  forms through `Form_QueryUnload` with `UnloadMode` `vbAppTaskManager`).
- An ARexx port, settings in `ENV:`/`ENVARC:` (`SaveSetting` for Save, `UseSetting` for Use),
  catalogs, numbers and dates in the user's format (`App.FormatNumber`, `App.FormatDate`),
  AmigaGuide help with a node per control (`helpnode=`) and a `$VER:` string make a program a
  full member of the desktop.

See also: [Forms and controls](12-forms.md), [Menus, toolbars, status bars and
dialogs](13-menus-dialogs.md), [Files and the system](10-files.md),
[Graphics](14-graphics.md), [Calling AmigaOS](17-amigaos.md),
[Networking](19-networking.md), [Extending Boing BASIC](20-extending.md).
