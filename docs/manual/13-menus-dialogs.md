# Menus, toolbars, status bars and dialogs

This chapter covers the parts of a program's user interface beyond the controls of
[chapter 12](12-forms.md): the menu bar, context and pop-up menus, toolbars, status bars, the
standard requesters (files, fonts, colours, screen modes, messages and questions), and the
services that make a program fit in with Workbench and other programs: icons and tooltypes,
drag and drop, iconifying, the clipboard, ARexx, AmigaGuide help, translations and printing.

Like forms, these work on AmigaOS 4. On other systems `boing check` checks the programs;
`MsgBox`, `InputBox`, `App.Request` and the clipboard also work there, on the console, so
console programs can use them.

## Menus

### The menu bar in the .afg

A form's menus are `menu` lines in its `.afg` file, after the root layout, at the left
margin. A `menu` at the left margin is a menu *title* in the menu bar; the `menu` lines
indented under it are its items, and items indented under an item are a sub-menu.
From `examples/book/ch13-menus-dialogs/menus`:

```text
# sketch.afg
window name=sketch title="Sketch" width=360 height=240 contextmenu=mnuWindow
vlayout id=root
  canvas id=view width=320 height=180 contextmenu=mnuCanvas
  label id=status text="Ready"
menu id=mnuProject text="Project"
  menu id=mnuNew text="New" key=N
  menu id=mnuOpen text="Open..." key=O
  menu id=mnuRecent text="Open recent"
    menu id=mnuNoRecent text="(none)" disabled=1
  menu text=-
  menu id=mnuAbout text="About..."
  menu id=mnuQuit text="Quit" key=Q
menu id=mnuView text="View"
  menu id=mnuGrid text="Grid" checkable=1 checked=1 key=G
  menu id=mnuRulers text="Rulers" checkable=1
  menu text=-
  menu id=mnuSmall text="Small" radio=1
  menu id=mnuNormal text="Normal" radio=1 checked=1
  menu id=mnuLarge text="Large" radio=1
menu id=mnuCanvas text="Canvas" hidden=1
  menu id=mnuClear text="Clear"
  menu id=mnuFillRed text="Fill red"
menu id=mnuWindow text="Window" hidden=1
  menu id=mnuHome text="Move to the top left"
```

| Key | Default | Meaning |
|---|---|---|
| `id` | | the menu's name in your code; its event sub is `<id>_Click` |
| `text` | `Menu` | the text; `text=-` makes a separator bar (which needs no `id`) |
| `key` | | the keyboard shortcut: one character, chosen with the right Amiga key and that key (`key=Q` is Amiga-Q). A longer text (`key="Ctrl Z"`) is only shown at the right of the item: handle such keys yourself in `Form_KeyDown` |
| `checkable` | 0 | 1 = an item with a checkmark that the user turns on and off |
| `checked` | 0 | 1 = the checkmark is on at first (checkable and radio items) |
| `radio` | 0 | 1 = one of a group: choosing it turns off the other `radio` items of the same menu |
| `disabled` | 0 | 1 = greyed out; on a title, the whole menu |
| `hidden` | 0 | 1 = not shown; a hidden title is a context or pop-up menu ([below](#context-menus)) |

Menus need intuition.library 54.6 or later (AmigaOS 4.1 Final Edition); without it the form
does not load.

The usual conventions on the Amiga: the first menu is called *Project* and ends with
*About...* and *Quit* (`key=Q`); an item that opens a requester ends with `...`.

### Menu events and properties

Choosing an item, with the mouse or its shortcut, calls `<id>_Click()`:

*Listing 13.1* (`examples/book/ch13-menus-dialogs/menus/menus.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/menus/menus.bbp -->
```basic
Private Sub mnuQuit_Click()
    Unload Me
End Sub

' --- View: a checkable item and a group of radio items ----------------------------------

Private Sub mnuGrid_Click()
    ' Checked is already the new state
    If mnuGrid.Checked Then status.Caption = "Grid on" Else status.Caption = "Grid off"
End Sub

Private Sub mnuSmall_Click(): SetSize "small": End Sub
Private Sub mnuNormal_Click(): SetSize "normal": End Sub
Private Sub mnuLarge_Click(): SetSize "large": End Sub

Private Sub SetSize(ByVal s As String)
    status.Caption = "Size " & s
    mnuView.Caption = "View (" & s & ")"      ' a menu title can change too
End Sub
```

Every menu with an `id` is a variable of the code-behind, with these properties:

| Property | Type | Design key | Notes |
|---|---|---|---|
| `Caption`, `Text` | String | `text` | |
| `Checked` | Boolean | `checked` | setting it on a plain item makes the item checkable |
| `Checkable` | Boolean | `checkable` | |
| `Enabled` | Boolean | `disabled` (the opposite) | also greys out the toolbar buttons linked to the item ([Toolbars](#toolbars)) |
| `Visible` | Boolean | `hidden` (the opposite) | |
| `Shortcut` | String | `key` | |
| `Name` | String, read-only | `id` | |
| `Tag` | String | | free for your program |

Change them at any time, for example to grey out *Save* while there is nothing to save:
`mnuSave.Enabled = False`. Menus have no methods; the form has the methods that add, remove
and pop up menus.

### Menus built at run time

`Me.AddMenu id, caption [, parent [, key]]` adds a menu while the program runs: with a
`parent` (the id of a title or item) as its last item, without one as a new title at the end
of the menu bar. `key` is its shortcut. `Me.RemoveMenu id` removes a menu, with its items,
whether it was added at run time or comes from the `.afg`. An id that is already used, or an
unknown parent, is error 5.

A menu added at run time has no variable in your code (the names are fixed when the program
is compiled): reach it with `Me.Controls(id)`. Its `Click` calls `<id>_Click` as usual, so
choose its ids in advance and write those subs. A list of recently opened files:

*Listing 13.2* (`examples/book/ch13-menus-dialogs/menus/menus.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/menus/menus.bbp -->
```basic
' a menu item added at run time for every file opened (up to three)
Private Sub AddRecent(ByVal file As String)
    If recentCount = 3 Then Exit Sub
    recentCount = recentCount + 1
    mnuNoRecent.Visible = False
    Me.AddMenu "mnuRecent" & recentCount, file, "mnuRecent", CStr(recentCount)
End Sub

' the Click subs of the run-time items exist from the start, with the ids AddRecent uses
Private Sub mnuRecent1_Click(): OpenRecent 1: End Sub
Private Sub mnuRecent2_Click(): OpenRecent 2: End Sub
Private Sub mnuRecent3_Click(): OpenRecent 3: End Sub

Private Sub OpenRecent(ByVal i As Integer)
    status.Caption = "Opened " & Me.Controls("mnuRecent" & i).Caption & " again"
End Sub
```

`examples/boingpad` keeps its recent files in the settings and rebuilds the sub-menu with
`RemoveMenu` and `AddMenu` each time the list changes.

### Context menus

A *context menu* opens when the user holds Shift or Ctrl and presses the right mouse button
over a control; it offers what can be done with that control. A plain right click always shows
the menu bar, as everywhere on AmigaOS. Make the context menu a `menu` title with `hidden=1`
(it doesn't show in the menu bar) and name it in the control's `contextmenu` key, or the
window's for the places that have none of their own. In the example above, Shift + right
button over the canvas opens `mnuCanvas`, anywhere else in the window `mnuWindow`.

- `contextmenukey=always` on the `window` line, or `Me.ContextMenuKey = 0` at run time, makes
  the window's context menus open with a plain right click (`Me.ContextMenuKey = 1` goes back to
  Shift or Ctrl). The menu bar then only opens where no context menu applies, so use this only in
  a window without a menu bar.

- At run time, `control.ContextMenu = "mnuCanvas"` sets a control's context menu and
  `control.ContextMenu = ""` removes it; `Me.ContextMenu` is the window's.
- `Me.ContextControl` is the id of the control the last context menu was opened over, so that
  one menu can serve several controls.
- The items' `Click` subs are the same as for menu-bar items; checkable and radio items work
  too.

`Me.PopupMenu menu [, x, y]` opens a hidden menu from code, at the pointer or at `x, y`
inside the window. `menu` is the menu variable or its id as a String. It returns after the user
chose an item (whose `Click` has run) or cancelled:

*Listing 13.3* (`examples/book/ch13-menus-dialogs/menus/menus.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/menus/menus.bbp -->
```basic
' a pop-up menu opened from code: double-click the canvas
Private Sub view_DblClick()
    Me.PopupMenu mnuCanvas
End Sub
```

On the Amiga the right mouse button belongs to the menus: in a window that has a menu bar or
context menus, a canvas gets right-button clicks only with `rmb=1`
([chapter 14](14-graphics.md#mouse-events)). Over such a canvas the right button always goes
to the canvas, also with Shift or Ctrl, so its context menu doesn't open there: offer the same
commands in the menu bar, or open the menu from code with `PopupMenu`.

## Toolbars

A toolbar is a row of buttons, usually with pictures, for the commands used most. It is a
`toolbar` in the layout holding `tool` objects (`examples/book/ch13-menus-dialogs/bars`):

```text
# writer.afg
window name=writer title="Writer" width=460 height=280
vlayout id=root
  toolbar id=tb
    tool id=tbNew text="New" image="TBImages:new" hint="A new text" menu=mnuNew
    tool id=tbOpen text="Open" image="TBImages:open" hint="Open a text" menu=mnuOpen
    tool id=tbSave text="Save" image="TBImages:save" hint="Save the text" menu=mnuSave
    tool separator=1
    tool id=tbFind text="Find" image="TBImages:search" hint="Show the find field" toggle=1
  texteditor id=ed
  string id=findText label="Find" maxchars=80
  statusbar id=sb panels="Ready|Ln 1|" widths="0|60|50"
menu id=mnuProject text="Project"
  menu id=mnuNew text="New" key=N
  menu id=mnuOpen text="Open..." key=O
  menu id=mnuSave text="Save" key=S disabled=1
  menu text=-
  menu id=mnuQuit text="Quit" key=Q
```

| Key (toolbar) | Meaning |
|---|---|
| `textonly` | 1 = only the texts, even where there are pictures |
| `imagesonly` | 1 = only the pictures |
| `vertical` | 1 = a column of buttons instead of a row |

| Key (tool) | Meaning |
|---|---|
| `id` | the tool's name in your code; its event sub is `<id>_Click` |
| `text` | the text, shown under the picture, or alone |
| `image` | the picture file (PNG, IFF, ... any picture the datatypes read) |
| `selimage` | a second picture for the pressed state |
| `hint` | the help bubble |
| `toggle` | 1 = the tool stays in or out when clicked (`Value` 1 or 0) |
| `checked` | 1 = a toggle tool starts pressed in |
| `disabled` | 1 = greyed out |
| `separator` | 1 = a gap instead of a button |
| `menu` | the id of a menu item this tool stands for |

**Pictures and the text fallback.** AmigaOS 4 comes with a set of toolbar pictures in the
drawer assigned to `TBImages:`, so `image="TBImages:open"` uses the system's own *Open*
picture. A toolbar shows pictures (with the texts) only if *every* tool's picture can be
loaded; if one is missing (another system may not have it), the whole bar shows the texts
only, so it never looks half finished. `textonly=1` and `imagesonly=1` choose a style
yourself. For pictures of your own, keep them beside the program and set the paths from code,
for example `tbNew.Picture = App.Path & "/images/new.png"`: in the `.afg`, `PROGDIR:` is the
drawer of the program that is running, which under `boing run` is the drawer of `boing`, not
of your program.

**Tools linked to menus.** A tool with `menu=mnuOpen` does what that menu item does: clicking
it calls `mnuOpen_Click`, and it is greyed out whenever `mnuOpen.Enabled` is `False`. Then each
command has one Sub, whether it is chosen from the menu, with its shortcut, or on the toolbar:

*Listing 13.4* (`examples/book/ch13-menus-dialogs/bars/bars.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/bars/bars.bbp -->
```basic
' the tools with menu= call these too, and follow their Enabled
Private Sub mnuNew_Click()
    ed.Text = ""
    ed.Modified = False
    mnuSave.Enabled = False             ' also greys out tbSave
    sb.Text = "New text"
End Sub

Private Sub tbFind_Click()              ' a toggle tool has its own Click; Value is 0 or 1
    findText.Visible = tbFind.Value = 1
    If tbFind.Value = 1 Then findText.SetFocus: sb.Panel(2) = "Find" Else sb.Panel(2) = ""
End Sub
```

| Property (tool) | Type | Design key | Notes |
|---|---|---|---|
| `Caption`, `Text` | String | `text` | |
| `Picture` | String | `image` | setting it loads another picture |
| `ToolTipText` | String | `hint` | |
| `Enabled` | Boolean | `disabled` (the opposite) | follows the linked menu item's `Enabled` |
| `Value` | Integer | `checked` | a toggle tool's state, 0 or 1 |
| `Visible` | Boolean | | remembered only: tools can't be hidden |

| Event | Sub |
|---|---|
| `Click` | `<id>_Click()` (for a tool with `menu=`, the menu's `Click` is called too) |

The toolbar itself has `ButtonCount` (read-only, separators included) and the properties every
control has ([chapter 12](12-forms.md#what-every-control-has)). A toolbar in a column keeps its
own height when the window is resized.

## Status bars

A status bar is a row of recessed text panels, usually at the bottom of the window:

```text
statusbar id=sb panels="Ready|Ln 1|" widths="0|60|50"
```

| Key | Default | Meaning |
|---|---|---|
| `panels` | `Ready` | the panels' starting texts, separated by `\|` |
| `widths` | | each panel's width in pixels; 0 = it takes the room left over |

| Property | Type | Notes |
|---|---|---|
| `Text`, `SimpleText` | String | panel 0 |
| `Panel(i)` | String | panel `i`, from 0; error 381 for a panel that doesn't exist |
| `PanelCount` | Long, read-only | |

A status bar has no events. Update it from other events, such as a text editor's
`CursorMove`:

*Listing 13.5* (`examples/book/ch13-menus-dialogs/bars/bars.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/bars/bars.bbp -->
```basic
Private Sub ed_CursorMove()
    sb.Panel(1) = "Ln " & (ed.CurrentLine + 1)
End Sub
```

## The CommonDialog

The *CommonDialog* opens the standard requesters: files, fonts, screen modes and colours.
Put one in the form's layout (it takes no room, like a timer), with the settings you want:

```text
commondialog id=dlg filter="Texts|#?.(txt|doc)" initdir="RAM:"
```

| Key | Meaning |
|---|---|
| `title` | the requester's title (`DialogTitle`) |
| `filter` | the files shown (`Filter`) |
| `initdir` | the drawer it starts in (`InitDir`) |
| `flags` | options, a number (`Flags`) |

Or make one in code, in any program, also without a form:

<!-- fragment -->
```basic
Dim dlg As Object
Set dlg = CreateObject("Boing.CommonDialog")
```

Set the properties, call a `Show` method, then read the result. Each `Show` method waits until
the requester is closed; meanwhile the program's windows show a busy pointer. The requesters
open on the program's screen, over its active window.

The results of two requesters can be put to use directly: a font from `ShowFont` becomes the
window's font with `Me.FontName = dlg.FontName` and `Me.FontSize = dlg.FontSize`, and a mode from
`ShowScreenMode` opens the program's own screen with `App.OpenScreen dlg.ScreenModeID,
dlg.ScreenWidth, dlg.ScreenHeight, dlg.ScreenDepth` (before the forms that should open on it are
loaded). Both are described in [The AmigaOS 4 desktop](18-desktop.md#screens).

### Methods

| Method | Requester |
|---|---|
| `ShowOpen` | the file requester, for choosing a file to load |
| `ShowSave` | the file requester in save mode |
| `ShowFont` | the font requester |
| `ShowColor` | a colour requester (red, green and blue sliders) |
| `ShowScreenMode` | the screen mode requester |
| `ShowMessage(prompt, buttons [, title [, icon]])` | a message with buttons of your own (see [App.Request](#requesters-with-your-own-buttons)) |

### Properties

| Property | Type | Notes |
|---|---|---|
| `DialogTitle` | String | the title; without one the requester has its own ("Open", "Save", "Font" ...) |
| `FileName` | String | the full path of the file chosen (the first one, with several); set it before `ShowOpen` / `ShowSave` to propose a file |
| `FileTitle` | String, read-only | the file name without the drawer |
| `InitDir` | String | the drawer to start in; after a requester it is the drawer the user was in |
| `Filter` | String | which files to show, as an AmigaDOS pattern: `#?.(iff\|png)`. A text before a `\|` is ignored, so `"Pictures\|#?.(iff\|png)"` gives the same |
| `Flags` | Long | the options below, added together |
| `FileCount` | Long, read-only | how many files were chosen |
| `Files(i)` | String, read-only | the full path of file `i` (from 0), with multiple selection |
| `Cancelled` | Boolean, read-only | `True` if the user cancelled the last requester |
| `CancelError` | Boolean | `True`: cancelling raises error 32755 (`cdlCancel`) instead |
| `FontName`, `FontSize` | String, Long | the font (`FontName` without `.font`, for example `"DejaVu Sans"`) |
| `FontBold`, `FontItalic`, `FontUnderline` | Boolean | the style chosen in the font requester |
| `Color` | Long | the colour, as made by `RGB()` |
| `ScreenModeID` | Long | the screen mode; set it to propose one |
| `ScreenWidth`, `ScreenHeight`, `ScreenDepth` | Long, read-only | the size and depth chosen |
| `Colors(i)`, `ColorCount` | Long | a palette (for `ShowPalette`, which isn't available yet) |

| Flag | Value | Meaning |
|---|---|---|
| `cdlOFNFileMustExist` | &H1000 | `ShowOpen`: only an existing file is accepted |
| `cdlOFNPathMustExist` | &H800 | accepted, but has no effect yet |
| `cdlOFNOverwritePrompt` | &H2 | `ShowSave`: ask before replacing an existing file |
| `cdlOFNAllowMultiselect` | &H200 | `ShowOpen`: several files can be chosen (`FileCount`, `Files(i)`) |
| `cdlOFNNoChangeDir` | &H8 | keep `InitDir` as it was |

### Examples

From `examples/book/ch13-menus-dialogs/dialogs`:

*Listing 13.6* (`examples/book/ch13-menus-dialogs/dialogs/dialogs.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/dialogs/dialogs.bbp -->
```basic
Private Sub openOne_Click()
    dlg.DialogTitle = "Open a text"
    dlg.Flags = cdlOFNFileMustExist
    dlg.ShowOpen
    If dlg.Cancelled Then Note "Open: cancelled": Exit Sub
    Note "Open " & dlg.FileName & " (file " & dlg.FileTitle & ")"
End Sub

Private Sub openMany_Click()
    Dim i As Long
    dlg.DialogTitle = "Open texts"
    dlg.Flags = cdlOFNAllowMultiselect
    dlg.ShowOpen
    If dlg.Cancelled Then Exit Sub
    For i = 0 To dlg.FileCount - 1
        Note "File " & (i + 1) & ": " & dlg.Files(i)
    Next
End Sub

Private Sub saveAs_Click()
    ' with CancelError, cancelling raises error 32755 (cdlCancel) instead
    dlg.CancelError = True
    dlg.DialogTitle = "Save the text"
    dlg.FileName = "RAM:untitled.txt"
    dlg.Flags = cdlOFNOverwritePrompt
    On Error GoTo cancelled
    dlg.ShowSave
    Note "Save as " & dlg.FileName
    dlg.CancelError = False
    Exit Sub
cancelled:
    dlg.CancelError = False
    If Err.Number = cdlCancel Then Note "Save: cancelled" Else Note "Error " & Err.Description
End Sub

Private Sub font_Click()
    dlg.FontName = "DejaVu Sans"
    dlg.FontSize = 14
    dlg.ShowFont
    If dlg.Cancelled Then Exit Sub
    Note "Font " & dlg.FontName & " " & dlg.FontSize & IIf(dlg.FontBold, " bold", "") & IIf(dlg.FontItalic, " italic", "")
    ' the window and its controls take the font (name and size)
    On Error GoTo noFont
    Me.FontName = dlg.FontName
    Me.FontSize = dlg.FontSize
    Exit Sub
noFont:
    Note "Can't use that font: " & Err.Description
End Sub

Private Sub colour_Click()
    dlg.Color = RGB(255, 128, 0)
    dlg.ShowColor
    If dlg.Cancelled Then Exit Sub
    Note "Colour &H" & Hex(dlg.Color)
End Sub

Private Sub screen_Click()
    dlg.ShowScreenMode
    If dlg.Cancelled Then Exit Sub
    ' App.OpenScreen dlg.ScreenModeID, dlg.ScreenWidth, ... would open a screen in this mode
    Note "Screen mode &H" & Hex(dlg.ScreenModeID) & ": " & dlg.ScreenWidth & " x " & dlg.ScreenHeight & " x " & dlg.ScreenDepth
End Sub
```

`Cancelled` is the simpler way to notice a cancel; `CancelError` suits code that already has
an error handler. A `getfile` control ([chapter 12](12-forms.md#file-chooser-getfile)) is a
file name field with its own requester button, for forms that show the chosen file.

## MsgBox and InputBox

### MsgBox

`MsgBox` shows a message in a requester and waits for a button:

```text
MsgBox prompt [, buttons [, title]]
result = MsgBox(prompt [, buttons [, title]])
```

`prompt` is the text (`vbLf` starts a new line). `title` is the requester's title; without it,
the program's name (`App.Title`). `buttons` is one value from each of these groups, added
together:

| Buttons | Value | The requester shows |
|---|---|---|
| `vbOKOnly` | 0 | OK (the default) |
| `vbOKCancel` | 1 | OK, Cancel |
| `vbAbortRetryIgnore` | 2 | Abort, Retry, Ignore |
| `vbYesNoCancel` | 3 | Yes, No, Cancel |
| `vbYesNo` | 4 | Yes, No |
| `vbRetryCancel` | 5 | Retry, Cancel |

| Icon | Value | For |
|---|---|---|
| `vbCritical` | 16 | an error |
| `vbQuestion` | 32 | a question |
| `vbExclamation` | 48 | a warning |
| `vbInformation` | 64 | information |

The constants `vbDefaultButton1` (0), `vbDefaultButton2` (256) and `vbDefaultButton3` (512)
are accepted but have no effect on AmigaOS. `MsgBox` takes two more arguments, a help file and
a help context, which are accepted and ignored.

The result says which button was chosen:

| Result | Value |
|---|---|
| `vbOK` | 1 |
| `vbCancel` | 2 |
| `vbAbort` | 3 |
| `vbRetry` | 4 |
| `vbIgnore` | 5 |
| `vbYes` | 6 |
| `vbNo` | 7 |

Each button has an underlined key, and closing the requester with Esc is the same as its last
button (Cancel, No, Ignore). A form isn't needed: `MsgBox` works in console programs too. It
opens over the program's active window, or on the Workbench screen if there is none.

### InputBox

`InputBox` asks for a line of text:

```text
text = InputBox(prompt [, title [, default]])
```

The requester has a text field holding `default`, with OK and Cancel. It returns the text, or
`""` if the user cancelled (so a program can't tell Cancel from an empty answer).

### On the console

On systems without AmigaOS both work on the console, which makes console programs that use
them testable: `MsgBox` prints the title in brackets and the prompt, and for Yes/No (and
Yes/No/Cancel) it waits for a line: `y` is Yes, `c` Cancel, anything else No. OK/Cancel waits
for `c` (Cancel) or anything else (OK); a message with only OK doesn't wait. `InputBox` prints
the prompt and reads a line; an empty line gives the default.

*Listing 13.7* (`examples/book/ch13-menus-dialogs/listing-13-07.bas`)

<!-- run stdin="n\nAnn" -->
```basic
Option Explicit
Dim answer As Long, name As String
answer = MsgBox("Save the changes?", vbYesNoCancel + vbQuestion, "Editor")
Select Case answer
Case vbYes: Print "saving"
Case vbNo: Print "not saving"
Case vbCancel: Print "cancelled"
End Select
name = InputBox("Your name?", "Hello", "Amiga")
If name = "" Then Print "no name" Else Print "Hello, "; name
MsgBox "Done", vbInformation
```

```output
[Editor] Save the changes?
(y/n) not saving
[Hello] Your name? Hello, Ann
Done
```

### Requesters with your own buttons

`App.Request(prompt, buttons [, title [, icon]])` shows a requester with buttons you name,
separated by `|`, with `_` before each button's key. It returns the number of the button
chosen: 1 for the leftmost, 2 for the next, and so on; Esc or the close gadget gives the last
(rightmost) one, so put Cancel last. `icon` is one of `vbCritical`, `vbQuestion`,
`vbExclamation`, `vbInformation`. `dlg.ShowMessage` of a CommonDialog does the same.

*Listing 13.8* (`examples/book/ch13-menus-dialogs/dialogs/dialogs.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/dialogs/dialogs.bbp -->
```basic
Private Sub choose_Click()
    Dim n As Long
    ' buttons from the left: 1, 2, 3; Esc or the close gadget gives the last
    n = dlg.ShowMessage("The picture has changed.", "_Save|_Discard|_Cancel", "Requesters", vbExclamation)
    Note "Button" & Str(n)
    ' the same without a CommonDialog control
    n = App.Request("Really quit?", "_Quit|_Stay")
    If n = 1 Then Unload Me
End Sub
```

On the console, `App.Request` prints the prompt and returns 1.

### An About requester

The *About...* item of the Project menu usually shows the program's name, version and author
in a requester. `MsgBox` with `vbInformation` is enough:

*Listing 13.9* (`examples/book/ch13-menus-dialogs/menus/menus.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/menus/menus.bbp -->
```basic
Private Sub mnuAbout_Click()
    MsgBox "Sketch 1.0" & vbLf & "A Boing BASIC menu example", vbInformation, "About Sketch"
End Sub
```

For a requester with a picture or links, make a small form of its own with `toolwindow=1` and
show it with `Show vbModal` ([chapter 12](12-forms.md#several-forms)).

## Workbench

The examples in this part come from `examples/book/ch13-menus-dialogs/workbench`, a note pad called
Jotter.

### Icons and tooltypes

A program started from Workbench can read the tooltypes of its icon (the lines in the icon's
Information window), and the files it was started with:

| Member | What it gives |
|---|---|
| `App.ToolType(name [, default])` | the value of the tooltype `NAME=value`; `"1"` for a bare `NAME`; `default` (or `""`) if there is none |
| `App.ToolTypeCount` | the number of tooltype lines |
| `App.ToolTypes(i)` | tooltype line `i` (from 0), as written |
| `App.FromWorkbench` | `True` if the program was started from Workbench |
| `App.ArgCount` | the number of files given to the program: project icons double-clicked, icons selected with it, or names on the Shell command line |
| `App.Arg(i)` | file `i` (from 0), with its full path |
| `App.ReadArgs(template)` | reads the arguments with an AmigaDOS template (`"FILE/A,SIZE/N,QUIET/S"`), or the tooltypes when started from Workbench; `True` if they fit |
| `App.ArgValue(key)` | a value after `ReadArgs`, as text |

The icon is the executable's: a native build has its own `.info`. Under `boing run` (also when
a project icon with the default tool `boing` starts the program) it is `Name.info` in the
program's drawer, `Name` being `App.EXEName`; without such an icon, `App.ToolType` gives the
default. Templates, and starting interpreted programs from Workbench, are described in
[chapter 18](18-desktop.md#arguments-templates-and-tooltypes).

*Listing 13.10* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
Private Sub Form_Load()
    App.HelpFile = App.Path & "/Jotter.guide"   ' the Help key opens it

    ' a tooltype of the program's icon: FONT=FIXED
    If UCase(App.ToolType("FONT", "")) = "FIXED" Then ed.FixedFont = True

    ' files given to the program: project icons, multi-selected icons, or the Shell
    If App.ArgCount > 0 Then LoadNote App.Arg(0)

    App.ARexxPort = "JOTTER"                ' other programs can now send commands
    status.Caption = App.Str(20, "ARexx port: ") & App.ARexxPortName
    If App.FromWorkbench Then status.Caption = status.Caption & " (started from Workbench)"
End Sub
```

`App.SaveIcon path [, defaultTool [, template]]` writes `path.info`, a project icon for a file
your program saved, so that double-clicking the file starts your program with it. The icon's
default tool is this program (or `defaultTool`); its picture comes from the icon file
`template`, or else the system's default project icon.

*Listing 13.11* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
Private Sub saveIt_Click()
    Dim path As String
    path = "RAM:note.txt"
    ed.SaveFile path
    If Dir(path & ".info") = "" Then App.SaveIcon path   ' a project icon: opens Jotter
    status.Caption = "Saved " & path
End Sub
```

The program's own icon (for a native build) is a file `Name.info` beside the executable; in a
project, the `Icon=` key names it for AmiForge and the build tools.

### Drag and drop from Workbench

A window with `dropfiles=1` in its `.afg` (or `Me.OLEDropMode = 1` in code) accepts icons
dragged onto it from Workbench. The drop calls:

| Sub | When |
|---|---|
| `Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)` | icons were dropped on the window; `X`, `Y` inside the window |
| `<id>_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)` | icons were dropped on a control with `dropfiles=1`; `X`, `Y` inside the control |

`Count` is the number of icons; their full paths are `App.DropFile(0)` to
`App.DropFile(Count - 1)` (also `App.DropCount`).

*Listing 13.12* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
Private Sub Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)
    LoadNote App.DropFile(0)
    If Count > 1 Then status.Caption = (Count - 1) & " more files ignored"
End Sub
```

### Iconifying

`iconify=1` on the window line adds an iconify gadget to the title bar. Clicking it closes the
window and puts an icon for it on Workbench; double-clicking that icon opens the window again.
The form stays loaded meanwhile, and its timers go on running. From code,
`Me.WindowState = 1` iconifies and `Me.WindowState = 0` opens the window again. `Form_Resize`
runs after both, so a program can tell:

*Listing 13.13* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
Private Sub hideIt_Click()
    Me.WindowState = 1                      ' iconify, as the iconify gadget does
End Sub

Private Sub Form_Resize()
    ' also after iconifying and uniconifying
    If Me.WindowState = 0 Then status.Caption = "Window open"
End Sub
```

`remember=1` on the window line makes the window open where the user last left it, at that
size ([chapter 12](12-forms.md#the-window-line)).

### AppIcons and Workbench menu items

| Member | What it does |
|---|---|
| `App.ShowAppIcon name [, iconfile]` | puts an icon of the running program on the Workbench screen, labelled `name`, with the picture of the icon `iconfile` (with or without `.info`); without one, the program's own icon or the default one |
| `App.HideAppIcon` | removes it |
| `App.AddAppMenuItem(text)` | adds an item to Workbench's Tools menu; returns its number |

Their events go to Subs with fixed names, which can be in any module (the startup form's
code-behind is looked at first):

| Sub | When |
|---|---|
| `AppIcon_DblClick()` | the AppIcon was double-clicked |
| `AppIcon_DragDrop(Count As Integer)` | icons were dropped on the AppIcon (`App.DropFile(i)`) |
| `AppMenu_Click(Index As Integer, Count As Integer)` | the Tools menu item `Index` was chosen, with `Count` icons selected in Workbench (`App.DropFile(i)`) |

*Listing 13.14* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
' an AppIcon: an icon of the running program on the Workbench screen
Private Sub mnuAppIcon_Click()
    If mnuAppIcon.Checked Then App.ShowAppIcon "Jotter" Else App.HideAppIcon
End Sub

Sub AppIcon_DblClick()                      ' the AppIcon was double-clicked
    Me.WindowState = 0
End Sub

Sub AppIcon_DragDrop(Count As Integer)      ' icons were dropped on the AppIcon
    LoadNote App.DropFile(0)
End Sub
```

Programs without forms receive these events (and ARexx commands) while they call `DoEvents`.

### Notifications, hotkeys and Exchange

| Member or Sub | What it does |
|---|---|
| `App.Notify title, text [, imagefile]` | shows a Ringhio notification, which goes away by itself; error 5 if it can't be shown |
| `App.HotKey name, keys` | a hotkey that works in every program (`"ctrl alt j"`), and an entry for the program in Exchange |
| `HotKey_Pressed(Name As String)` | the hotkey `Name` was pressed |
| `App_Show()`, `App_Hide()`, `App_Quit()` | Exchange's Show, Hide and Remove buttons, or the same request from another program through application.library |

These Subs, too, can be in any module. A program with a hotkey should always have an
`App_Quit` that does what its Quit menu item does (for example `Unload Me`). In a form's
code, a hotkey that brings the window to the front is a line in `Form_Load` and a Sub:

<!-- fragment -->
```basic
App.HotKey "popup", "ctrl alt j"            ' Ctrl-Alt-J anywhere: HotKey_Pressed("popup")

Sub HotKey_Pressed(Name As String)
    Me.WindowState = 0                      ' open the window if it is iconified
    Me.SetFocus                             ' and bring it to the front
End Sub
```

The details, with Exchange and application.library, are in
[The AmigaOS 4 desktop](18-desktop.md#commodities-a-hotkey-and-exchange).

## The clipboard

| Member | What it does |
|---|---|
| `Clipboard.SetText text` | puts text on the clipboard |
| `Clipboard.GetText()` | the text on the clipboard, `""` if there is none |
| `Clipboard.Clear` | empties the clipboard |
| `Clipboard.SetPicture canvas [, imageId]` | puts a canvas's picture (or one of its images) on the clipboard, as an IFF picture |
| `Clipboard.GetPicture(canvas)` | copies the clipboard's picture into the canvas; `True` if there was one |
| `Clipboard.GetImage(canvas)` | makes the clipboard's picture a new image of the canvas and returns its id; 0 if there is none |
| `Clipboard.HasPicture` | `True` if the clipboard holds a picture |

Text goes through the clipboard as Latin-1. Other programs see what you put there at once, and
`GetText` sees what they copy. On other systems the clipboard is the program's own (other
programs don't see it), and there are no pictures:

*Listing 13.15* (`examples/book/ch13-menus-dialogs/listing-13-15.bas`)

<!-- run -->
```basic
Option Explicit
Clipboard.SetText "Boing!"
Print Clipboard.GetText()
Clipboard.Clear
Print "["; Clipboard.GetText(); "]"
```

```output
Boing!
[]
```

The text editor control has its own `Cut`, `Copy` and `Paste` methods, which use the same
clipboard. Canvases and images are in [chapter 14](14-graphics.md).

## ARexx

ARexx is the Amiga's way for programs to control each other. A program that opens an *ARexx
port* can be sent commands by ARexx scripts and by other programs.

### Receiving commands

`App.ARexxPort = "JOTTER"` opens a port of that name. Port names are upper case, so
`"jotter"` also opens `JOTTER`; if the name is in use, the port is `JOTTER.1`, then
`JOTTER.2` and so on, and `App.ARexxPortName` is the name actually used. `App.ARexxPort = ""`
closes the port. Every command that arrives
calls the Sub `ARexx_Command`, which can be in any module:

*Listing 13.16* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
' --- ARexx: address JOTTER; 'TEXT' gives the text, 'APPEND words' adds a line -----------

Private Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Select Case UCase(Cmd)
    Case "TEXT": Result = ed.Text
    Case "APPEND": ed.Text = ed.Text & vbLf & Args
    Case "QUIT": Unload Me
    Case Else: App.ARexxRC = 10            ' an error for the caller
    End Select
End Sub
```

- `Cmd` is the first word of the command, `Args` the rest of the line. Commands are not
  case-sensitive by convention, hence `UCase`.
- Whatever the Sub puts in `Result` goes back to the script as `RESULT` (the script needs
  `OPTIONS RESULTS`).
- `App.ARexxRC` is the return code the script sees as `RC`: 0 (the default) for success, 5
  for a warning, 10 or 20 for errors. Without an `ARexx_Command` Sub every command fails with
  RC 30.

A script that talks to Jotter:

```text
/* jotter.rexx */
OPTIONS RESULTS
ADDRESS JOTTER
'APPEND Bought milk'
'TEXT'
SAY RESULT
```

### Sending commands

| Member | What it does |
|---|---|
| `App.SendARexx(port, command)` | sends `command` to the port named `port` and waits for the answer; returns its `RESULT`, with the `RC` in `App.ARexxRC`. Error 5 if there is no such port |
| `App.RunARexx script` | starts an ARexx script (a file) and goes on at once, without waiting |

Don't start a script that talks to your own port with `Shell "rx script"`: `Shell` waits for
`rx`, `rx` waits for your program, and your program, waiting in `Shell`, can't answer. Use
`App.RunARexx`, which doesn't wait. `App.SendARexx` to your own port calls your
`ARexx_Command` directly.

The ports are served while the program waits for events, that is between event subs in a form
program, and in `DoEvents` in a program without forms.

## AmigaGuide help

| Member | What it does |
|---|---|
| `App.ShowHelp file [, node]` | opens an AmigaGuide document at a node (`main` if none is given) in its own window; the program goes on running |
| `App.HelpFile` | an AmigaGuide file: the Help key, pressed in any of the program's windows, opens it |

*Listing 13.17* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
Private Sub mnuHelp_Click()
    App.ShowHelp App.Path & "/Jotter.guide", "main"
End Sub
```

A small AmigaGuide file (`Jotter.guide` in the example) looks like this:

```text
@database Jotter.guide
@node main "Jotter"
Jotter is a small note pad, an example of the Boing BASIC manual.

  @{"Commands" link commands}
@endnode
@node commands "ARexx commands"
ADDRESS JOTTER

  TEXT           returns the text
  APPEND words   adds a line
  QUIT           ends Jotter
@endnode
```

## Locale catalogs

AmigaOS translates programs with *catalogs*: files with the program's texts in another
language, installed in `LOCALE:Catalogs/<language>/` or in a `Catalogs` drawer beside the
program, and chosen from the user's Locale preferences.

| Member | What it does |
|---|---|
| `App.OpenCatalog name [, builtinLanguage]` | opens the catalog `name` (for example `"jotter.catalog"`) in the user's preferred language; `builtinLanguage` is the language of the texts in your program (English if left out). Returns `True` if a catalog was found |
| `App.Str(id, default)` | text number `id` of the catalog, or `default` when there is no catalog or no such text |
| `App.Language` | the language in use, for example `"english"` |

Texts in the `.afg` can be translated too: write them as `"$id:default"`, and the form uses
the catalog's text `id` when it loads:

```text
window name=jotterWin title="$1:Jotter" width=400 height=220 remember=1 iconify=1 dropfiles=1
vlayout id=root
  texteditor id=ed
  hlayout even=1 weight=0
    button id=copyAll text="$2:_Copy all"
```

The texts are looked up as the form loads, before its `Form_Load` runs, so the catalog must be
open by then. Jotter therefore starts in `Sub Main`, which opens the catalog and then shows the
form (whose window has a name of its own, `jotterWin`, so that `start.bas` can reach it):

*Listing 13.18* (`examples/book/ch13-menus-dialogs/workbench/workbench.bbp`)

<!-- project: examples/book/ch13-menus-dialogs/workbench/workbench.bbp -->
```basic
' start.bas - opens the catalog before the first form loads, so that the form's
' "$id:default" texts are translated too
Option Explicit

Sub Main()
    App.OpenCatalog "jotter.catalog"        ' translations, if a catalog is installed
    jotterWin.Show vbModal                  ' the window is named jotterWin in jotter.afg
End Sub
```

Without a catalog, every text is its default, so a program can be written with `$id:` texts
from the start and translated later.

## Printing

The `Printer` object prints through the printer set up in the Printer preferences:

| Member | What it does |
|---|---|
| `Printer.Print text` | prints a line of text |
| `Printer.Write text` | prints text without ending the line |
| `Printer.NewPage` | starts a new page |
| `Printer.EndDoc` | ends the document: the printer gets everything |
| `Printer.KillDoc` | throws away what was printed since the last `EndDoc` |
| `Printer.PaintPicture canvas [, x, y, w, h]` | prints a canvas's picture |
| `Printer.ShowSetup` | opens the printer preferences |
| `Printer.Page` | the current page number |

The Printer object has not been tested with real printers yet. On systems without AmigaOS it
doesn't exist (error 438).

## Settings

Programs keep their preferences with `GetSetting`, `SaveSetting` and `DeleteSetting`, which
store them in `ENV:` and `ENVARC:` under the program's name, and `App.EnvPath` is a drawer
there for files of your own. These are described with the other system functions in
[chapter 10](10-files.md).

## Summary

- Menus are `menu` lines after the root layout: titles, items, sub-items, with `key`
  shortcuts, `checkable`, `radio` and `disabled` items, and `<id>_Click` subs. `AddMenu` and
  `RemoveMenu` change them at run time; hidden titles are context menus (`contextmenu=`) and
  pop-up menus (`PopupMenu`).
- A `toolbar` of `tool`s, linked to menu items with `menu=`, uses `TBImages:` pictures and
  falls back to texts; a `statusbar` shows text panels.
- Context menus open with Shift or Ctrl + right button (`contextmenukey=always` for a plain
  right click); the right button alone shows the menu bar.
- The CommonDialog's `ShowOpen`, `ShowSave`, `ShowFont`, `ShowColor`, `ShowScreenMode` and
  `ShowMessage` open the standard requesters; `Me.FontName` / `Me.FontSize` apply a chosen
  font and `App.OpenScreen` a chosen screen mode. `MsgBox`, `InputBox` and `App.Request` ask
  quick questions.
- The App object connects a program to Workbench (tooltypes, arguments and `ReadArgs`
  templates, drops, icons, AppIcons, iconify), notifications (`App.Notify`), hotkeys and
  Exchange (`App.HotKey`, `App_Quit`), ARexx (`ARexxPort`, `ARexx_Command`, `SendARexx`), AmigaGuide help and
  catalogs; `Clipboard` and `Printer` do what their names say.

See also: [Forms and controls](12-forms.md), [Graphics](14-graphics.md),
[Files and the system](10-files.md), [Using AmiForge](03-amiforge.md).
