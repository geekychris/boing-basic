# Forms and controls

This chapter is about programs with windows. A window is a *form*: a layout file (`.afg`) that
describes the window and the controls in it, and a BASIC module, the form's *code-behind*,
with a Sub for every event you want to handle. The chapter describes the `.afg` format, how
events reach your code, the form's own properties, methods and events, and every control with
its properties, methods and events. It ends with several forms in one program, the keyboard,
timers, and testing form programs on a computer without AmigaOS. Menus, toolbars, status bars
and requesters have [chapter 13](13-menus-dialogs.md); drawing in a form is
[chapter 14](14-graphics.md).

Form programs run on AmigaOS 4. On other systems you can `boing check` them (and run them
without a display, see [Testing without a display](#testing-without-a-display)).

## A first form

A form program is a project of (at least) three files. The project file names the form and
makes it the startup:

```ini
# Hello: the smallest form program (manual chapter 12)
Name=Hello
Startup=Form hello
Form=hello.afg
```

`Form=hello.afg` adds the layout `hello.afg` and its code-behind, the module `hello.bas` (the
same name with `.bas`). `Startup=Form hello` opens the form named `hello` when the program
starts, and the program runs until that form (and any other) is closed.

The layout, `hello.afg`:

```text
# hello.afg - the layout of the form
window name=hello title="Hello" width=260 height=0
vlayout id=root
  string id=who label="Your name" text="Amiga"
  hlayout even=1
    button id=greet text="_Greet"
    button id=quit text="_Quit"
  label id=answer text=" "
```

And the code-behind, `hello.bas`:

*Listing 12.1* (`examples/book/ch12-forms/hello/hello.bbp`)

<!-- project: examples/book/ch12-forms/hello/hello.bbp -->
```basic
' hello.bas - the code-behind of hello.afg
Option Explicit

Private Sub Form_Load()
    answer.Caption = "Type a name and press Greet"
End Sub

Private Sub greet_Click()
    answer.Caption = "Hello, " & who.Text & "!"
End Sub

Private Sub who_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then greet_Click     ' Return in the text field
End Sub

Private Sub quit_Click()
    Unload Me
End Sub
```

Run it on the Amiga with `boing run hello.bbp`, or build it with `boing build hello.bbp`
([chapter 2](02-shell.md)). In AmiForge, the form designer writes the `.afg` file for you and
adds the event subs ([chapter 3](03-amiforge.md)); this chapter shows the files themselves, so
that you know what every setting does.

Every control with an `id` is a variable of the code-behind: `who.Text`, `answer.Caption`.
Every event is a Sub named after the control and the event: `greet_Click`. The form itself is
`Me`, and its events are `Form_Load`, `Form_Unload` and so on, whatever the window's name.

## The .afg file

An `.afg` file is plain text, one object per line:

```text
kind key=value key="value with spaces" ...
```

- `kind` is the object: `window`, `vlayout`, `button`, ...
- Values without spaces can be written bare (`width=260`); others go in double quotes. Inside
  quotes, `\"` is a quote, `\\` a backslash and `\n` a new line.
- Indentation (spaces or tabs) gives the structure: an object belongs to the nearest line
  above it that is indented less.
- Lines starting with `#` are comments, and so is everything after a `#` that stands where a
  key would. Empty lines are ignored.
- Keys the runtime doesn't know are ignored, so a misspelt key silently does nothing.

The file has this shape:

1. one `window` line (it can be anywhere, but is usually first);
2. one *root layout*, a `vlayout` or `hlayout` at the left margin, with everything in the
   window indented under it;
3. after the root layout, optionally, the menus: `menu` lines at the left margin with their
   items indented under them ([chapter 13](13-menus-dialogs.md)).

A mistake in the structure stops the form from loading, with a message such as
`hello.afg:3: the root must be a vlayout or hlayout`. The rules: only one root layout; only
layouts, toolbars, tabs and menus can contain objects; a toolbar holds only `tool` objects and
tools go only in a toolbar; menus hold only menus; every page of `tabs` is a layout.

### Texts and translations

A text value written as `"$12:Open..."` is looked up in the program's catalog when the form
loads: string 12 of the catalog, or `Open...` when there is no catalog or no string 12. That
lets one `.afg` file show the user's language ([chapter 13](13-menus-dialogs.md#locale-catalogs)).

In a control's `text` or `label` value, an underscore marks the next letter as the control's
keyboard shortcut and is not shown itself: `text="_Quit"` shows *Quit* with the Q underlined,
and pressing Q clicks the button ([Shortcut letters](#shortcut-letters-return-and-esc)). A
text field, number field or text editor takes its letter from `label` only: its `text` is what
the user types, so an underscore there is an ordinary character. (In menus and toolbar buttons
the underscore is simply left out; menus have their own shortcuts, see
[chapter 13](13-menus-dialogs.md).)

### The window line

| Key | Default | Meaning |
|---|---|---|
| `name` | `main` | the form's name in your code (`hello.Show`) |
| `title` | `Untitled` | the window title (`Caption`) |
| `width`, `height` | 0 | the size of the inside of the window in pixels; 0 = as small as the controls allow |
| `resizable` | 1 | 0 = no size gadget |
| `remember` | 0 | 1 = the window's position and size are saved when it closes (in `ENVARC:` under the program's title) and used when it opens again |
| `iconify` | 0 | 1 = an iconify gadget ([chapter 13](13-menus-dialogs.md#iconifying)) |
| `toolwindow` | 0 | 1 = no size or depth gadget (small dialogs and palettes) |
| `dropfiles` | 0 | 1 = icons can be dropped on the window ([chapter 13](13-menus-dialogs.md#drag-and-drop-from-workbench)) |
| `contextmenu` | | the id of a hidden menu that Shift or Ctrl + the right mouse button opens over the window ([chapter 13](13-menus-dialogs.md#context-menus)) |
| `contextmenukey` | | `always` = context menus open with a plain right click (then the menu bar can't be reached over them) |
| `mousemove` | 0 | 1 = `Form_MouseMove` for every move, not only while a button is held |
| `helpnode` | | the AmigaGuide node the Help key opens over the window where no control has a node of its own; `main` if not given ([chapter 13](13-menus-dialogs.md#amigaguide-help)) |
| `font`, `fontsize` | | the font of the window and all its controls, for example `font="DejaVu Sans" fontsize=15`; the screen's font if not given. `fontsize` alone keeps the screen's font at that size |
| `screentitle` | | the text of the screen's title bar while the window is active (`ScreenTitle`) |
| `pubscreen` | | the name of a public screen to open on; the default public screen if there is none of that name |
| `screen` | | `own` = the program's own screen (opened with the window if it isn't open yet); `workbench` = the default public screen even when the program has its own |
| `screenmode`, `screenwidth`, `screenheight`, `screendepth` | | with `screen=own`: the new screen's mode (a `ScreenModeID`, as `0x50011000`), size and depth; the Workbench's for those not given |
| `fullscreen` | 0 | 1 = no border, no gadgets, and the window covers its whole screen (on the program's own screen, that screen's title bar is hidden too) |
| `borderless` | 0 | 1 = no border, title bar or gadgets |
| `backdrop` | 0 | 1 = a backdrop window, behind all the other windows of its screen |

The window opens centred on the screen, unless `remember=1` and it was open before, or it is
a `fullscreen=1` window. Screens, full-screen windows and fonts are explained with examples in
[The AmigaOS 4 desktop](18-desktop.md#screens).

### Layouts: vlayout and hlayout

Controls are not placed at pixel positions. A `vlayout` stacks its contents in a column, an
`hlayout` puts them in a row, and layouts nest. The layout gives every control at least the
room it needs, shares out the rest, and does it again when the window is resized, so you
never compute positions.

| Key (on a layout) | Meaning |
|---|---|
| `title` | a frame with this title around the contents (a group) |
| `frame` | the kind of frame: `none` (the default, or `group` when there is a `title`), `group`, `button` (a raised box), `field` (a recessed box) |
| `even` | 1 = all children get the same size (a row of equal buttons) |
| `splitter` | 1 = bars between the children that the user can drag to share the space differently |

Every object inside a layout can also have these keys, which tell its layout how to place it:

| Key (on a child) | Meaning |
|---|---|
| `weight` | how much of the spare space it gets, compared with the others (default 100 each). `weight=0` keeps it at its smallest size: buttons beside a text field, a row of buttons at the bottom |
| `label` | a text label at the left of the control (`string id=who label="Name"`) |
| `minwidth`, `minheight` | at least this many pixels |

A preferences window that uses most of them (`examples/book/ch12-forms/layout`):

```text
# prefs.afg - a preferences window
window name=prefs title="Preferences" width=420 height=260 remember=1
vlayout id=root
  tabs id=pages selected=0
    vlayout title="General"
      vlayout title="You"
        string id=userName label="Name" text=""
        string id=email label="E-mail" text=""
      hlayout frame=field
        checkbox id=autosave text="Save every"
        integer id=minutes value=5 min=1 max=60 weight=0 minwidth=60
        label text="minutes"
      space
    hlayout title="Folders" splitter=1
      listbrowser id=folders items="Work:|RAM:|DH1:Projects" weight=30
      vlayout weight=70
        label id=folderInfo text="Choose a folder"
        space
  hlayout even=1 weight=0
    button id=ok text="_OK"
    button id=cancel text="_Cancel"
```

The two pages of `tabs` are layouts, and their `title` is the tab's label rather than a frame.
A `space` takes up spare room, here pushing the rest of a page to the top. Objects without an
`id` (the label "minutes") are drawn but can't be reached from code.

The code-behind of this window reads and saves its settings with `GetSetting` and
`SaveSetting` ([chapter 10](10-files.md)):

*Listing 12.2* (`examples/book/ch12-forms/layout/layout.bbp`)

<!-- project: examples/book/ch12-forms/layout/layout.bbp -->
```basic
' prefs.bas
Option Explicit

Private Sub Form_Load()
    userName.Text = GetSetting("LayoutDemo", "User", "Name", "")
    email.Text = GetSetting("LayoutDemo", "User", "Email", "")
    autosave.Value = Val(GetSetting("LayoutDemo", "Files", "AutoSave", "1"))
    minutes.Value = Val(GetSetting("LayoutDemo", "Files", "Minutes", "5"))
    minutes.Enabled = autosave.Value = vbChecked
End Sub

Private Sub autosave_Click()
    minutes.Enabled = autosave.Value = vbChecked
End Sub

Private Sub pages_Click()
    Me.Caption = "Preferences - " & pages.TabCaption(pages.Tab)
End Sub

Private Sub folders_Click()
    folderInfo.Caption = "Folder " & folders.Text
End Sub

Private Sub ok_Click()
    SaveSetting "LayoutDemo", "User", "Name", userName.Text
    SaveSetting "LayoutDemo", "User", "Email", email.Text
    SaveSetting "LayoutDemo", "Files", "AutoSave", CStr(autosave.Value)
    SaveSetting "LayoutDemo", "Files", "Minutes", CStr(minutes.Value)
    Unload Me
End Sub

Private Sub cancel_Click()
    Unload Me
End Sub
```

### Keys every control has

| Key | Meaning |
|---|---|
| `id` | the control's name in your code; without one, code can't reach the control |
| `disabled` | 1 = greyed out at first (`Enabled = False`) |
| `hint` | a help bubble shown when the pointer rests on it (`ToolTipText`); with a `statusbar hints=1` in the window, also shown in the status bar while the pointer is over the control |
| `helpnode` | the AmigaGuide node the Help key opens while the pointer is over the control (`HelpNode`; [chapter 13](13-menus-dialogs.md#amigaguide-help)) |
| `contextmenu` | the id of a hidden menu that Shift or Ctrl + the right mouse button opens over the control ([chapter 13](13-menus-dialogs.md#context-menus)) |
| `dropfiles` | 1 = icons dropped on this control go to its own `OLEDragDrop` event |
| `font`, `fontsize` | a font for this control alone; with only `fontsize`, the window's font (or the screen's font) at that size |
| `label` | (in a layout) a label beside the control; a `_` in it marks the control's shortcut letter, for the controls that have one ([Shortcut letters](#shortcut-letters-return-and-esc)) |

The keys of each kind of control are in the [control reference](#the-controls) below.

## The code-behind

The code-behind is an ordinary module with three extras:

- **Control variables.** Every object of the `.afg` with an `id` is a module-level variable
  of that name, holding the control. You don't declare them, and `Option Explicit` knows them. (A layout's `id`, such as `root`,
  is also a name, but it holds no control.)
  Their type is `Object`, so their members are late bound: a misspelt property is run-time
  error 438, not a compile error.
- **Event subs.** When something happens to a control, the runtime calls the Sub named
  `<id>_<Event>` in the code-behind, if there is one: `greet_Click`, `who_Change`,
  `tick_Timer`. Events of the form itself call `Form_<Event>`: `Form_Load`, `Form_Resize`.
  Events without a Sub are ignored, so write only those you need. The name is all that
  connects a Sub to its event; the subs are usually `Private`.
- **Me** is the form: `Me.Caption = "Busy"`, `Unload Me`.

An event sub must have the parameters listed for that event in this chapter (for example
`Private Sub who_KeyPress(KeyAscii As Integer)`). Some are `ByRef` on purpose, so that the
sub can answer: setting `Cancel = True` in `Form_QueryUnload` keeps the window open.

Events run one at a time: while an event sub runs, the window doesn't react, and the next
event waits. Keep event subs short. A long job can call `DoEvents` now and then to let other
events through ([chapter 10](10-files.md)), or be cut into steps run by a
[Timer](#timer-controls).

Setting a property from code generally doesn't fire the control's event, with these
exceptions, which follow common practice: setting `Text` of a text field or text editor fires
its `Change`; setting `Value` of a check box fires `Click`; setting `ListIndex` of a list,
chooser or radio group fires `Click`; setting `Value` of a slider or scroller fires `Change`;
setting `Tab` of tabs fires `Click`, and `SelectedKey` of a tree view fires `NodeClick`.

An event sub that stops with an unhandled run-time error ends the program with the usual
message ([chapter 8](08-errors.md)).

### Reaching a form from other modules

Other modules reach a form by its window name, `name=` in the `.afg` (`hello.Show`), and a
control of it as `form.control` (`hello.answer.Caption = "Hi"`).

The form's code-behind is also a module, named after its file (`hello.bas` is the module
`hello`), and its `Public` variables and procedures are reached as `module.name`. The window
name and the module name may be the same, and usually are: then one name reaches both, so
`hello.Show` and `hello.Caption` are the form, and `hello.Answer` a Public variable of its
code-behind. They may also differ, as in the dialog of the [multiple forms](#several-forms)
example: file `person.afg`, `window name=dlgPerson`. Then `dlgPerson.Show` is the form and
`person.Answer` a Public variable of its code-behind.

A window name must not be the name of anything else of the program that other modules can
reach: another module, a class, or a `Public` procedure or variable. That would make the name
mean two things, so it is a compile error:

```text
prefs.bas:1:1: error: the form 'Settings' has the same name as the procedure 'Settings' in module main: rename the window (window name=) or the other
```

The same goes for a form named `main` in a program that has a module `main.bas`, or a form
named like a class. Rename the window, or the other thing.

## The form

### Properties

| Property | Type | Design key | Notes |
|---|---|---|---|
| `Name` | String, read-only | `name` | |
| `Caption` | String | `title` | the window title |
| `Width`, `Height` | Long | `width`, `height` | the inside of the window, in pixels; setting them resizes the window |
| `Left`, `Top` | Long | | the window's position on the screen |
| `Visible` | Boolean | | `True` shows the window, `False` hides it (`Show` / `Hide`) |
| `Enabled` | Boolean | | `False`: a busy pointer and no input, while the program works |
| `WindowState` | Integer | | 0 open, 1 iconified (needs `iconify=1`) |
| `MousePointer` | Integer | | the pointer shape over the window ([chapter 14](14-graphics.md)) |
| `ContextMenu` | String | `contextmenu` | ([chapter 13](13-menus-dialogs.md#context-menus)) |
| `ContextControl` | String, read-only | | the control the last context menu was opened over |
| `ContextMenuKey` | Long | `contextmenukey` | 1 (the default): context menus open with Shift or Ctrl + right button; 0: with any right click |
| `ScreenTitle` | String | `screentitle` | the screen's title while the window is active |
| `FontName`, `FontSize` | String, Long | `font`, `fontsize` | the window's font (`""` and 0 if it has none of its own); setting either gives the window and its controls the new font and lays the window out again. Error 380 if the font can't be opened |
| `ScreenWidth`, `ScreenHeight` | Long, read-only | | the size of the window's screen, in pixels |
| `OLEDropMode` | Integer | `dropfiles` | 1 = icons can be dropped on the window |
| `Tag` | String | | free for your program |

### Methods

| Method | What it does |
|---|---|
| `Show [vbModal]` | loads the form if needed and opens its window (or brings it to the front). With `vbModal` (1) it returns only when the form is hidden or unloaded, and the program's other windows take no input meanwhile |
| `Hide` | closes the window; the form and its controls stay loaded, with their values |
| `Move left [, top [, width [, height]]]` | moves (and resizes) the window |
| `SetFocus` | brings the window to the front and makes it the active one |
| `Refresh` | lays out and redraws the window |
| `Controls(name)` | a control by its id, as a String: `Me.Controls("b" & i).Caption` |
| `PopupMenu`, `AddMenu`, `RemoveMenu` | menus, see [chapter 13](13-menus-dialogs.md) |

And the statements:

| Statement | What it does |
|---|---|
| `Load form` | loads the form (`Form_Load` runs) without opening its window |
| `Unload form` | unloads it: `Form_QueryUnload` and `Form_Unload` run (either can cancel), the window closes, the controls go away. `Unload Me` from its own code |
| `End` | ends the program at once: windows close without `QueryUnload` / `Unload` |

A form is loaded the first time you use it: `hello.Caption = "x"` loads `hello` (running its
`Form_Load`) without showing it. The program ends when the last loaded form is unloaded.
Closing a window with its close gadget is the same as `Unload`, with `UnloadMode` 0.

**Placing the window.** Set `Left`, `Top`, `Width` and `Height` in `Form_Load` and the window
opens there; set them (or call `Move`) later and the open window moves and changes size:

<!-- fragment -->
```basic
Private Sub Form_Load()
    Me.Left = 20            ' the window opens 20 pixels from the left edge...
    Me.Top = 40             ' ...and 40 from the top
End Sub

Private Sub corner_Click()
    Me.Move 0, 0            ' later: move the open window to the top-left corner
End Sub
```

### Events

| Event | Sub | When |
|---|---|---|
| `Load` | `Form_Load()` | the form is loaded, before its window opens: set the controls up here |
| `Activate` | `Form_Activate()` | the window opened or became the active window |
| `Deactivate` | `Form_Deactivate()` | another window became the active one |
| `Resize` | `Form_Resize()` | after the window opened, after every size change, and after iconifying and opening again |
| `QueryUnload` | `Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)` | the form is about to be unloaded; `UnloadMode` is 0 (`vbFormControlMenu`) for the close gadget, 1 (`vbFormCode`) for `Unload` in code, 3 (`vbAppTaskManager`) when the system asks the program to quit (Exchange's Remove, [chapter 18](18-desktop.md#quit-hide-and-show-from-the-system)). `Cancel = True` keeps it |
| `Unload` | `Form_Unload(Cancel As Integer)` | the form is being unloaded (after `QueryUnload`); `Cancel = True` keeps it. Save settings here |
| `KeyDown` | `Form_KeyDown(KeyCode As Integer, Shift As Integer)` | a key went down ([The keyboard](#the-keyboard)) |
| `KeyUp` | `Form_KeyUp(KeyCode As Integer, Shift As Integer)` | a key was released |
| `KeyPress` | `Form_KeyPress(KeyAscii As Integer)` | a key that types a character was pressed |
| `MouseDown`, `MouseUp`, `MouseMove`, `DblClick`, `MouseWheel` | as for a canvas | the mouse, outside every control ([chapter 14](14-graphics.md)) |
| `OLEDragDrop` | `Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)` | icons were dropped on the window ([chapter 13](13-menus-dialogs.md#drag-and-drop-from-workbench)) |

The order: `Form_Load`, the window opens, `Form_Activate`, `Form_Resize`, then the events the
user causes; at the end the close gadget or `Unload`, `Form_QueryUnload`, `Form_Unload`, and
the window closes.

## What every control has

| Property / method | Type | Design key | Notes |
|---|---|---|---|
| `Name` | String, read-only | `id` | |
| `Enabled` | Boolean | `disabled` (the opposite) | a disabled control is greyed out and ignores the user |
| `Visible` | Boolean | | a hidden control takes no room: the window is laid out again |
| `ToolTipText` | String | `hint` | the help bubble (and the status bar's help line with `hints=1`) |
| `HelpNode` | String | `helpnode` | the help node for the Help key; `""` if none |
| `ContextMenu` | String | `contextmenu` | the id of a hidden menu |
| `Tag` | String | | free for your program |
| `Left`, `Top`, `Width`, `Height` | Long, read-only | | where the layout put the control, in pixels inside the window |
| `SetFocus` | method | | puts the cursor into a text field, number field or text editor; does nothing for other controls |
| `Refresh` | method | | redraws the control |

Labels, spaces and fuel gauges can't be used by the user: of these, use `Name`, `Visible`,
`Tag` and the position.

A control written without a property name means its *default property*: `Text` where the
control has one, else `Caption`, else `Value`. So `who = "Ann"` sets `who.Text`, and
`Print volume` prints the slider's value. Writing the property is clearer.

`TypeName(control)` gives the kind: `CommandButton`, `TextBox`, `IntegerBox`, `CheckBox`,
`ComboBox` (chooser), `OptionGroup` (radio), `Slider`, `ScrollBar`, `ListBox`, `Label`,
`Space`, `ProgressBar` (fuel gauge), `FileChooser`, `TextEditor`, `Timer`, `Menu`, `Toolbar`,
`ToolButton`, `StatusBar`, `CommonDialog`, `TabStrip`, `TreeView`, `Grid`, `Image`, and
`Canvas`.

Errors: assigning a read-only property is error 383 ("Set not supported (read-only
property)"), a property the control doesn't have is 438, a list index out of range 381, an
invalid `ListIndex` 380, and using a control of a form that was unloaded is error 364.

## The controls

The basic controls in one window (`examples/book/ch12-forms/controls`):

```text
# controls.afg
window name=controls title="Controls" width=380 height=0
vlayout id=root
  hlayout
    vlayout title="Choices"
      checkbox id=sound text="_Sound" checked=1
      radio id=size items="Small|Medium|Large" selected=1
      chooser id=colour items="Red|Green|Blue" selected=0 label="Colour"
    vlayout title="Numbers"
      slider id=volume min=0 max=64 level=32 label="Volume"
      scroller id=pos total=100 visible=10 top=0 label="Position"
      integer id=copies value=1 min=1 max=99 label="Copies"
      fuelgauge id=meter min=0 max=64 level=32
  hlayout
    string id=title label="Title" text="Untitled" maxchars=40 hint="The document's title"
    button id=apply text="_Apply" weight=0
    space
    button id=reset text="_Reset" weight=0 disabled=1
  label id=status text="Ready"
```

*Listing 12.3* (`examples/book/ch12-forms/controls/controls.bbp`)

<!-- project: examples/book/ch12-forms/controls/controls.bbp -->
```basic
' controls.bas - every event of the basic controls updates the status line
Option Explicit

Private Sub Form_Load()
    colour.AddItem "Yellow"             ' a fourth choice
    status.Caption = "Ready: " & colour.ListCount & " colours"
End Sub

Private Sub Report(ByVal what As String)
    status.Caption = what
    reset.Enabled = True
End Sub

Private Sub sound_Click()
    If sound.Value = vbChecked Then Report "Sound on" Else Report "Sound off"
End Sub

Private Sub size_Click()
    Report "Size " & size.Text & " (" & size.ListIndex & ")"
End Sub

Private Sub colour_Click()
    Report "Colour " & colour.Text
End Sub

Private Sub volume_Scroll()             ' while the knob is dragged
    meter.Value = volume.Value
End Sub

Private Sub volume_Change()             ' the knob was let go
    meter.Value = volume.Value
    Report "Volume" & Str(volume.Value)
End Sub

Private Sub pos_Change()
    Report "Position" & Str(pos.Value)
End Sub

Private Sub copies_Change()
    Report copies.Value & " copies"
End Sub

Private Sub title_Change()               ' every key typed
    Me.Caption = "Controls - " & title.Text
End Sub

Private Sub apply_Click()
    Report "Title """ & title.Text & """, " & copies.Value & " copies, volume" & Str(volume.Value)
End Sub

Private Sub reset_Click()
    sound.Value = vbChecked             ' fires sound_Click
    size.ListIndex = 1                  ' fires size_Click
    colour.ListIndex = 0                ' fires colour_Click
    volume.Value = 32                   ' fires volume_Change
    copies.Value = 1
    title.Text = "Untitled"             ' fires title_Change
    status.Caption = "Reset"
    reset.Enabled = False
End Sub
```

In the tables below, *Design key* is the `.afg` key that gives a property its first value; a
property without one can only be set from code. Indexes count from 0, and `ListIndex = -1`
means nothing is selected.

### Button (`button`)

A push button.

| Key | Default | Meaning |
|---|---|---|
| `text` | `Button` | the caption; `_` marks the shortcut letter, which clicks the button |
| `default` | 0 | 1 = Return clicks the button (OK, Save) |
| `cancel` | 0 | 1 = Esc clicks the button (Cancel) |
| `image` | | a picture file (any format the datatypes read: PNG, IFF, JPEG, ...) shown on the button, beside the text if there is one; `text=""` for a picture only |
| `selimage` | | a second picture, shown while the button is pressed |

| Property | Type | Notes |
|---|---|---|
| `Caption`, `Text` | String | the same thing; setting it lays the window out again |

| Event | Sub |
|---|---|
| `Click` | `<id>_Click()` |

### Text field (`string`)

A one-line text entry field.

| Key | Default | Meaning |
|---|---|---|
| `text` | | the starting text |
| `maxchars` | 128 | the most characters it takes |

| Property | Type | Notes |
|---|---|---|
| `Text` | String | setting it fires `Change` |
| `MaxLength` | Long | `maxchars` |
| `Locked` | Boolean | `True`: the user can't change the text |
| `SelStart` | Long | the cursor position (characters from the start) |
| `SelLength` | Long | always 0: a text field has no selection you can read |

| Event | Sub | When |
|---|---|---|
| `Change` | `<id>_Change()` | the text changed: after every key typed, and when code sets `Text` |
| `KeyPress` | `<id>_KeyPress(KeyAscii As Integer)` | the user finished the entry: `KeyAscii` is 13 for Return, 9 for Tab. Other keys don't arrive here |

Tab and Shift-Tab move the cursor from one text or number field to the next.

### Number field (`integer`)

A field for a whole number, with arrow buttons.

| Key | Default | Meaning |
|---|---|---|
| `value` | 0 | the number |
| `min`, `max` | 0, 100 | the range |

| Property | Type | Notes |
|---|---|---|
| `Value` | Long | |
| `Text` | String | the number as text |
| `Min`, `Max` | Long | |

| Event | Sub | When |
|---|---|---|
| `Change` | `<id>_Change()` | a number was typed (and Return or Tab pressed), or an arrow clicked |

### Check box (`checkbox`)

| Key | Default | Meaning |
|---|---|---|
| `text` | `Check box` | the label; `_` marks the shortcut letter, which ticks or clears it |
| `checked` | 0 | 1 = ticked |

| Property | Type | Notes |
|---|---|---|
| `Caption`, `Text` | String | the label |
| `Value` | Integer | `vbUnchecked` (0) or `vbChecked` (1); setting it fires `Click` |

| Event | Sub | When |
|---|---|---|
| `Click` | `<id>_Click()` | the box was ticked or cleared (`Value` is already the new state) |

### Radio buttons (`radio`)

A group of buttons of which exactly one is on. The whole group is one control: there is one
`id`, and the buttons are its items, numbered from 0.

| Key | Default | Meaning |
|---|---|---|
| `items` | `One\|Two` | the labels, separated by `\|` |
| `selected` | 0 | which one is on |

| Property | Type | Notes |
|---|---|---|
| `ListIndex`, `Value` | Long | which button is on; setting it fires `Click` |
| `ListCount` | Long, read-only | the number of buttons |
| `List(i)` | String, read-only | a button's label |
| `Text` | String, read-only | the label of the button that is on |

| Event | Sub |
|---|---|
| `Click` | `<id>_Click()` |

The buttons are fixed when the form loads: radio groups have no `AddItem`.

### Chooser (`chooser`)

A pop-up list to pick one item from (a drop-down list).

| Key | Default | Meaning |
|---|---|---|
| `items` | `One\|Two\|Three` | the items, separated by `\|` |
| `selected` | 0 | the item shown |

| Property / method | Type | Notes |
|---|---|---|
| `ListIndex` | Long | the chosen item; setting it fires `Click` (-1 is not allowed: error 380) |
| `ListCount` | Long, read-only | |
| `List(i)` | String | an item (read and write) |
| `Text` | String, read-only | the chosen item |
| `AddItem text [, index]` | method | adds an item at the end, or before position `index` |
| `RemoveItem index` | method | |
| `Clear` | method | removes all items |

| Event | Sub | When |
|---|---|---|
| `Click` | `<id>_Click()` | the user chose an item |

### List (`listbrowser`)

A scrolling list of rows, optionally with columns.

| Key | Meaning |
|---|---|
| `items` | the starting rows, separated by `\|` |
| `columns` | column titles, separated by `\|`: `columns="Name\|Size\|Date"`. The rows' cells are then separated by tabs |
| `widths` | the columns' share of the width: `widths="50\|20\|30"` |
| `sortable` | 1 = clicking a column title sorts the list by that column |
| `multiselect` | 1 = several rows can be selected |

| Property / method | Type | Notes |
|---|---|---|
| `ListIndex` | Long | the selected row, -1 for none; setting it fires `Click` and scrolls the row into view |
| `ListCount` | Long, read-only | |
| `List(i)` | String | a row (read and write); with columns, the cells joined by `vbTab` |
| `Text` | String, read-only | the selected row |
| `TopIndex` | Long | the first row shown (scrolling) |
| `AddItem text [, index]` | method | a row at the end, or before `index`: `files.AddItem "readme" & vbTab & "1024"` |
| `RemoveItem index` | method | |
| `Clear` | method | |
| `ColumnCount` | Long, read-only | |
| `ColumnTitle(col)` | String | |
| `Cell(row, col)` | String | one cell (read and write) |
| `Selected(i)` | Boolean | whether row `i` is selected (with `multiselect=1`) |
| `SelCount` | Long, read-only | how many rows are selected |
| `ItemData(i)` | Long | a number kept with row `i` for your program; it moves with its row when the list is sorted |
| `SortColumn`, `SortOrder` | Long | the column the list is sorted by, and 0 ascending or 1 descending; setting either sorts |
| `Sort [col [, order]]` | method | sorts now; cells that are numbers sort as numbers |

| Event | Sub | When |
|---|---|---|
| `Click` | `<id>_Click()` | a row was selected |
| `DblClick` | `<id>_DblClick()` | a row was double-clicked (after its `Click`) |
| `ColumnClick` | `<id>_ColumnClick(Column As Integer)` | a column title was clicked (with `sortable=1`, after the list was sorted) |

From `examples/book/ch12-forms/lists`, a list with columns:

```text
listbrowser id=files columns="Name|Size|Type" widths="50|20|30" sortable=1 multiselect=1
```

*Listing 12.4* (`examples/book/ch12-forms/lists/lists.bbp`)

<!-- project: examples/book/ch12-forms/lists/lists.bbp -->
```basic
Private Sub files_Click()
    If files.ListIndex >= 0 Then
        fileInfo.Caption = files.Cell(files.ListIndex, 0) & ", " & files.Cell(files.ListIndex, 1) & " bytes"
    End If
End Sub

Private Sub files_ColumnClick(Column As Integer)
    fileInfo.Caption = "Sorted by " & files.ColumnTitle(Column)
End Sub

Private Sub removeFiles_Click()
    Dim i As Long
    For i = files.ListCount - 1 To 0 Step -1     ' from the end: the rows below move up
        If files.Selected(i) Then files.RemoveItem i
    Next
    fileInfo.Caption = files.ListCount & " files"
End Sub
```

### Label (`label`)

A line of text the user can't change.

| Key | Default | Meaning |
|---|---|---|
| `text` | `Text` | the text |

| Property | Type |
|---|---|
| `Caption`, `Text` | String |

Labels have no events. A label whose text will change needs room for the longest text: give
it a long starting text, or a `minwidth`.

A `_` in a label's text gives its letter to the control after it, as a caption for a field
usually does: `label text="_Port"` followed by `integer id=port` shows **P**ort with the P
underlined, and P puts the cursor into the number field ([Shortcut
letters](#shortcut-letters-return-and-esc)).

### Space (`space`)

Empty room that takes spare space in its layout (`weight` sets how much). No properties beyond
`Visible`, no events.

### Slider (`slider`)

| Key | Default | Meaning |
|---|---|---|
| `min`, `max` | 0, 100 | the range |
| `level` | 0 | the value |
| `vertical` | 0 | 1 = an upright slider |

| Property | Type | Notes |
|---|---|---|
| `Value` | Long | setting it fires `Change` |
| `Min`, `Max` | Long | |

| Event | Sub | When |
|---|---|---|
| `Scroll` | `<id>_Scroll()` | while the knob is being dragged, at every new value |
| `Change` | `<id>_Change()` | the knob was released at a new value |

### Scroller (`scroller`)

A scroll bar, for scrolling something your program draws.

| Key | Default | Meaning |
|---|---|---|
| `total` | 100 | the size of the whole thing (`Max`) |
| `visible` | 10 | how much of it is shown at once: the knob's size (`LargeChange`) |
| `top` | 0 | the position (`Value`), 0 to `total - visible` |
| `vertical` | 0 | 1 = an upright scroller |

| Property | Type | Notes |
|---|---|---|
| `Value` | Long | setting it fires `Change` |
| `Max` | Long | `total` |
| `LargeChange` | Long | `visible` |

| Event | Sub | When |
|---|---|---|
| `Scroll` | `<id>_Scroll()` | while being dragged |
| `Change` | `<id>_Change()` | released at a new position |

### Progress bar (`fuelgauge`)

Shows how far a job has got.

| Key | Default | Meaning |
|---|---|---|
| `min`, `max` | 0, 100 | the range |
| `level` | 50 | the value |

| Property | Type | Notes |
|---|---|---|
| `Value` | Long | |
| `Min`, `Max` | Long | |
| `Text` | String | a text shown in the bar instead of the percentage; `""` shows the percentage again |
| `ShowPercent` | Boolean | whether the percentage is shown |

No events. While your program works in a loop, call `DoEvents` after changing `Value`, or the
bar is not redrawn until the loop ends.

### File chooser (`getfile`)

A file name field with a button that opens the file requester.

| Key | Default | Meaning |
|---|---|---|
| `title` | `Choose a file` | the requester's title |
| `pattern` | | the files to show, as an AmigaDOS pattern: `#?.(txt\|bas)` |
| `save` | 0 | 1 = a requester for saving |

| Property / method | Type | Notes |
|---|---|---|
| `FileName`, `Text` | String | the full path, as typed or chosen |
| `DialogTitle` | String | `title` |
| `Pattern` | String | `pattern` |
| `SaveMode` | Boolean | `save` |
| `ShowOpen` | method | opens the requester from code; `FileName` is `""` when the user cancels |

| Event | Sub | When |
|---|---|---|
| `Change` | `<id>_Change()` | a file was chosen in the requester (not when it was cancelled) |

For requesters without a field in the window, use the CommonDialog
([chapter 13](13-menus-dialogs.md#the-commondialog)).

### Text editor (`texteditor`)

A multi-line text editor with a scroll bar, undo, cut and paste.

| Key | Meaning |
|---|---|
| `text` | the starting text (`\n` for new lines) |
| `fixedfont` | 1 = a fixed-width font |

| Property / method | Type | Notes |
|---|---|---|
| `Text` | String | all the text, lines separated by `vbLf`; setting it fires `Change` |
| `Locked` | Boolean | read only |
| `Modified` | Boolean | changed since it was loaded, or since you set it to `False` |
| `LineCount` | Long, read-only | |
| `CurrentLine`, `CurrentColumn` | Long | the cursor, counted from 0; setting them moves it |
| `SelStart`, `SelLength` | Long | the selection, in characters from the start |
| `SelText` | String | the selected text; setting it replaces the selection |
| `FixedFont` | Boolean | |
| `TabSize` | Long | |
| `Bold`, `Italic`, `Underline` | Boolean | the style of the selection, or at the cursor |
| `CanUndo`, `CanRedo` | Boolean, read-only | |
| `Cut`, `Copy`, `Paste`, `Undo`, `Redo`, `SelectAll` | methods | as the Edit menu does them |
| `Clear` | method | removes all the text |
| `InsertText text` | method | at the cursor |
| `Find(text [, matchCase [, fromTop]])` | method | finds the next match after the cursor (or from the top) and selects it; returns `True` if found |
| `Replace(find, with [, all [, matchCase]])` | method | replaces the next match after the cursor, or (with `all` True) every match in the text; returns how many |
| `LoadFile path`, `SaveFile path` | methods | read or write a whole text file, and set `Modified` to `False`. A file that can't be read is error 53, one that can't be written error 75 |

| Event | Sub | When |
|---|---|---|
| `Change` | `<id>_Change()` | the text changed (also while typing) |
| `CursorMove` | `<id>_CursorMove()` | the cursor moved: update a status line here |

From `examples/book/ch12-forms/editor`, a small notes window:

*Listing 12.5* (`examples/book/ch12-forms/editor/editor.bbp`)

<!-- project: examples/book/ch12-forms/editor/editor.bbp -->
```basic
Private Sub ed_CursorMove()
    status.Caption = "Ln " & (ed.CurrentLine + 1) & ", Col " & (ed.CurrentColumn + 1)
End Sub

Private Sub findNext_Click()
    If findText.Text = "" Then findText.SetFocus: Exit Sub
    If Not ed.Find(findText.Text, matchCase.Value = vbChecked) Then
        ' not found below the cursor: try again from the top
        If Not ed.Find(findText.Text, matchCase.Value = vbChecked, True) Then status.Caption = "Not found"
    End If
End Sub
```

### Tabs (`tabs`)

A row of tabs over pages; only one page shows at a time. Each child of `tabs` is a page, which
must be a `vlayout` or `hlayout`; its `title` is the tab's label.

| Key | Default | Meaning |
|---|---|---|
| `selected` | 0 | the page shown first |

| Property | Type | Notes |
|---|---|---|
| `Tab`, `Value` | Long | the page shown, from 0; setting it fires `Click` |
| `TabCount` | Long, read-only | |
| `TabCaption(i)` | String | a tab's label |

| Event | Sub | When |
|---|---|---|
| `Click` | `<id>_Click()` | another tab was chosen |

### Tree view (`treeview`)

A list of nodes in a hierarchy that the user can open and close. Every node has a key (a
String, unique in the tree), a text, and the key of its parent (`""` for a node at the top).

| Property / method | Notes |
|---|---|
| `AddNode key, parentKey, text` | adds a node under `parentKey` (`""` = at the top); error 457 if `key` is in use |
| `RemoveNode key` | removes the node and everything under it |
| `Clear` | removes all nodes |
| `Expand key`, `Collapse key` | opens or closes a node |
| `NodeText(key)` | the node's text; `NodeText key, text` changes it |
| `NodeParent(key)` | the parent's key, `""` for a top node |
| `NodeExpanded(key)` | `True` if it is open |
| `NodeCount` | Long, read-only: the number of nodes |
| `SelectedKey` | String: the selected node; setting it opens its parents, selects it and fires `NodeClick` |
| `EventKey` | String, read-only: the node of the last `Expand` or `Collapse` event |

| Event | Sub | When |
|---|---|---|
| `NodeClick` | `<id>_NodeClick()` | a node was selected (`SelectedKey`) |
| `DblClick` | `<id>_DblClick()` | a node was double-clicked |
| `Expand` | `<id>_Expand()` | the user opened a node (`EventKey`) |
| `Collapse` | `<id>_Collapse()` | the user closed a node (`EventKey`) |

*Listing 12.6* (`examples/book/ch12-forms/lists/lists.bbp`)

<!-- project: examples/book/ch12-forms/lists/lists.bbp -->
```basic
Private Sub tree_NodeClick()
    Dim k As String
    k = tree.SelectedKey
    nodeInfo.Caption = tree.NodeText(k) & " (parent: " & tree.NodeParent(k) & ")"
End Sub

Private Sub tree_Expand()
    nodeInfo.Caption = "Opened " & tree.NodeText(tree.EventKey)
End Sub
```

The tree in that example is filled in `Form_Load`:

<!-- fragment -->
```basic
tree.AddNode "sys", "", "SYS:"
tree.AddNode "c", "sys", "C"
tree.AddNode "work", "", "Work:"
tree.AddNode "games", "work", "Games"
tree.Expand "sys"
```

### Grid (`grid`)

A table of cells the user can move around in and type into, for spreadsheets and data entry.
The first rows and columns can be fixed titles that don't scroll.

| Key | Default | Meaning |
|---|---|---|
| `rows`, `cols` | 10, 5 | the size, title rows and columns included |
| `fixedrows`, `fixedcols` | 1, 1 | how many title rows and columns |
| `headers` | 0 | 1 = the titles are filled with A, B, C ... and 1, 2, 3 ... |
| `colwidth` | 64 | the column width in pixels |
| `editable` | 1 | typing on a cell edits it |

| Property / method | Type | Notes |
|---|---|---|
| `Rows`, `Cols` | Long | |
| `FixedRows`, `FixedCols` | Long | |
| `Row`, `Col` | Long | the current cell (from 0, title rows and columns included) |
| `Text` | String | the current cell; setting it sets every selected cell |
| `TextMatrix(row, col)` | String | any cell (read and write) |
| `ColWidth(col)` | Long | a column's width; `ColWidth = n` sets all of them |
| `RowHeight` | Long | |
| `ColAlignment(col)` | Long | `flexAlignLeft` (0), `flexAlignRight` (1), `flexAlignCenter` (2); by default numbers are on the right |
| `CellBold(row, col)` | Boolean | also without indexes, for the current cell |
| `CellForeColor(row, col)`, `CellBackColor(row, col)` | Long | colours made with `RGB`; also without indexes |
| `TopRow`, `LeftCol` | Long | the first row and column shown (scrolling) |
| `SelStartRow`, `SelStartCol`, `SelEndRow`, `SelEndCol` | Long | the selected block |
| `Editable` | Boolean | |
| `Editing` | Boolean, read-only | a cell is being edited now |
| `Redraw` | Boolean | `False` while you fill many cells, then `True` to draw them all at once |
| `AddItem text [, row]` | method | adds a row; its cells separated by `vbTab` |
| `RemoveItem row` | method | |
| `Clear` | method | empties the cells (not the titles) |
| `EditCell` | method | starts editing the current cell |

| Event | Sub | When |
|---|---|---|
| `LeaveCell` | `<id>_LeaveCell()` | the current cell is about to change |
| `EnterCell` | `<id>_EnterCell()` | the current cell changed |
| `BeforeEdit` | `<id>_BeforeEdit(Row As Long, Col As Long, Cancel As Integer)` | editing a cell is about to start; `Cancel = True` stops it |
| `AfterEdit` | `<id>_AfterEdit(Row As Long, Col As Long)` | an edit was finished (Return, Tab, a cursor key, a click elsewhere), or Del cleared cells |
| `Click`, `DblClick` | `<id>_Click()`, `<id>_DblClick()` | a double click also starts editing |
| `KeyDown` | `<id>_KeyDown(KeyCode As Integer, Shift As Integer)` | a key while the grid has the input; `KeyCode = 0` throws the key away |
| `Scroll` | `<id>_Scroll()` | the grid scrolled |

The keys: cursor keys move (with Shift they extend the selection), Tab and Return move on,
Page Up / Page Down, Home and End, F2 edits the cell, Del clears the selected cells, Esc
cancels an edit.

*Listing 12.7* (`examples/book/ch12-forms/lists/lists.bbp`)

<!-- project: examples/book/ch12-forms/lists/lists.bbp -->
```basic
Private Sub sheet_BeforeEdit(Row As Long, Col As Long, Cancel As Integer)
    If Col = 3 Then Cancel = True           ' the totals are computed, not typed
End Sub

Private Sub sheet_AfterEdit(Row As Long, Col As Long)
    sheet.TextMatrix(Row, 3) = CStr(Val(sheet.TextMatrix(Row, 2)) * 2)
End Sub
```

`examples/minisheet` is a larger spreadsheet built on the grid.

### Image (`image`)

A picture from a file.

| Key | Meaning |
|---|---|
| `file` | the picture file (PNG, IFF, JPEG, ... whatever the datatypes read) |
| `frame` | 1 = a recessed frame around it |

| Property | Type | Notes |
|---|---|---|
| `Picture` | String | the file; setting it shows another picture |

No events. A missing or unreadable file shows nothing, without an error.

### Timer controls

A `timer` runs code at regular intervals. It is not visible and takes no room, so its line can
go anywhere in the layout.

| Key | Default | Meaning |
|---|---|---|
| `interval` | 0 | milliseconds between events; 0 = never |
| `enabled` | 1 | 0 = stopped at first |

| Property | Type | Notes |
|---|---|---|
| `Interval` | Long | setting it starts the count again |
| `Enabled` | Boolean | `False` stops the timer, `True` starts it (the next event one interval later) |

| Event | Sub | When |
|---|---|---|
| `Timer` | `<id>_Timer()` | every `Interval` milliseconds, while `Enabled` and the form is loaded |

Timer events never overlap: if a `Timer` sub is still running when the next event is due, that
event is skipped. A stopwatch (`examples/book/ch12-forms/timer`):

```text
# watch.afg
window name=watch title="Stopwatch" width=220 height=0
vlayout id=root
  label id=display text="0.0 s"
  fuelgauge id=minute min=0 max=600 level=0
  hlayout even=1
    button id=startStop text="_Start"
    button id=clear text="C_lear"
  timer id=tick interval=100 enabled=0
  timer id=clock interval=1000
```

*Listing 12.8* (`examples/book/ch12-forms/timer/timer.bbp`)

<!-- project: examples/book/ch12-forms/timer/timer.bbp -->
```basic
' watch.bas
Option Explicit

Private tenths As Long

Private Sub tick_Timer()                ' every 100 ms while tick.Enabled
    tenths = tenths + 1
    display.Caption = Format(tenths / 10, "0.0") & " s"
    minute.Value = tenths Mod 600
End Sub

Private Sub clock_Timer()               ' every second: the time of day in the title
    Me.Caption = "Stopwatch - " & Format(Now, "hh:nn:ss")
End Sub

Private Sub startStop_Click()
    tick.Enabled = Not tick.Enabled
    If tick.Enabled Then startStop.Caption = "_Stop" Else startStop.Caption = "_Start"
End Sub

Private Sub clear_Click()
    tenths = 0
    display.Caption = "0.0 s"
    minute.Value = 0
End Sub
```

Counting events, as here, is fine for a display, but timers can be late when the system is
busy: for exact times, read the clock (`Timer`, `Now`) in the event. Timers that drive
animation and games are in [chapter 14](14-graphics.md#the-game-loop).

### Canvas (`canvas`)

A drawing surface for graphics and games:
`canvas id=view width=320 height=200`. Its drawing methods, mouse events and keys are
[chapter 14](14-graphics.md).

### Menus, toolbars, status bars and the CommonDialog

`menu`, `toolbar`, `tool`, `statusbar` and `commondialog` objects are described in
[chapter 13](13-menus-dialogs.md). One `statusbar` key concerns every control: with
`hints=1`, the status bar's first panel shows the `hint=` of the control under the pointer
([chapter 13](13-menus-dialogs.md#status-bars)).

## The keyboard

### Keyboard focus

The window that is active gets the keys. Inside it, a text field, number field or text editor
that has the cursor takes the typing; `control.SetFocus` puts the cursor into one (for example
in `Form_Activate`), and Tab moves between text and number fields. Keys that no field takes
work the controls' shortcuts (next section), or else go to the form's key events.

Other controls don't take the keyboard focus, and `SetFocus` does nothing for them. There is no
`ActiveControl` property.

### Shortcut letters, Return and Esc

The letter after a `_` in a control's `text` or `label` is its shortcut. While no text field
has the cursor, pressing that letter, alone or with Shift, works the control:

| Control | The letter comes from | The shortcut letter |
|---|---|---|
| button | `text` (else `label`) | clicks it: `<id>_Click` runs |
| check box | `text` (else `label`) | ticks or clears it; `Click` runs |
| text field, number field, text editor | `label` only | puts the cursor into it |
| chooser, radio buttons, tabs, list | `text` (else `label`) | selects the next item (with Shift the previous one), going round at the end; `Click` runs |
| label | `text` | works the next field, button, check box, chooser, radio buttons or list after it in the `.afg`, as that control's own letter would |

Only these controls have shortcuts: a `_` in the `label` of a slider, scroller, file chooser,
tree view or grid marks no letter, and leaves that letter free for the others. A disabled or
hidden control has no shortcut. With an Amiga key or Ctrl held, the letter is
left to the menus (`key=`) and to your key events. `default=1` on a button makes Return click
it, and `cancel=1` makes Esc click it: the usual OK and Cancel of a dialog.

```text
window name=ask title="Rename" width=0 height=0 resizable=0
vlayout id=root
  string id=newName label="_New name"
  checkbox id=keepIcon text="_Keep the icon" checked=1
  hlayout even=1
    button id=ok text="_Rename" default=1
    button id=cancel text="_Cancel" cancel=1
```

Here N puts the cursor into the field, K switches the check box, R or Return renames, and C or
Esc cancels. While the field has the cursor, the typing goes to the field, shortcut letters
included; Return there ends the entry and arrives in the field's `KeyPress`, so
`If KeyAscii = 13 Then ok_Click` there lets Return in the field rename as well.

A key used by a shortcut, and Return and Esc when a `default=1` or `cancel=1` button takes
them, do not reach `Form_KeyDown`, `Form_KeyPress` or `Form_KeyUp`: neither the press nor the
release arrives. In a game window, keep the letters the
game uses free of `_` shortcuts.

### Key events

| Event | Sub | When |
|---|---|---|
| `KeyDown` | `Form_KeyDown(KeyCode As Integer, Shift As Integer)` | a key went down, and again and again while it is held (key repeat) |
| `KeyUp` | `Form_KeyUp(KeyCode As Integer, Shift As Integer)` | the key was released |
| `KeyPress` | `Form_KeyPress(KeyAscii As Integer)` | after `KeyDown`, for a key that types a character: `KeyAscii` is the character's code in the keymap the user has chosen (Latin-1) |

The form gets these only while no text field or editor has the cursor. `Shift` holds the
qualifier keys, added together:

| Value | Constant | Key |
|---|---|---|
| 1 | `vbShiftMask` | either Shift |
| 2 | `vbCtrlMask` | Ctrl |
| 4 | `vbAltMask` | either Alt |
| 8 | | either Amiga key |

Test one with `And`: `If Shift And vbShiftMask Then ...`.

`KeyCode` identifies the key, not the character, so it is the same whatever the keymap:

| Keys | Codes |
|---|---|
| A to Z | `vbKeyA` (65) to `vbKeyZ` (90) |
| 0 to 9 (main keyboard) | `vbKey0` (48) to `vbKey9` (57) |
| F1 to F10 | `vbKeyF1` (112) to `vbKeyF10` (121) |
| cursor keys | `vbKeyLeft` (37), `vbKeyUp` (38), `vbKeyRight` (39), `vbKeyDown` (40) |
| Return, Enter | `vbKeyReturn` (13) |
| Esc | `vbKeyEscape` (27) |
| Space | `vbKeySpace` (32) |
| Tab | `vbKeyTab` (9) |
| Backspace | `vbKeyBack` (8) |
| Del | `vbKeyDelete` (46) |
| Help | `vbKeyHelp` (47) |
| left / right Shift | `vbKeyLShift` (160), `vbKeyRShift` (161) |
| Ctrl | `vbKeyControl` (17) |
| left / right Alt | `vbKeyLMenu` (164), `vbKeyRMenu` (165) |
| left / right Amiga | `vbKeyLWin` (91), `vbKeyRWin` (92) |
| Caps Lock | `vbKeyCapital` (20) |
| every other key | 256 + the key's raw key code |

"Every other key" includes the punctuation keys, the numeric keypad, and keys such as Home,
End, Page Up and Page Down where the keyboard has them: they arrive as 256 + their raw code
(the numeric keypad's 7, for example, is raw code &H3D, so 256 + 61 = 317). Constants such as
`vbKeyHome`, `vbKeyPageUp` and `vbKeyNumpad0` exist, but these keys do not arrive with those
values. To find a key's code, print it from `Form_KeyDown`.

The Shift, Ctrl, Alt and Amiga keys arrive as `KeyDown` and `KeyUp` events of their own, so a
program can tell left from right. A canvas can also be asked whether a key is down at any time
(`view.KeyDown(vbKeyLeft)`, [chapter 14](14-graphics.md#the-keyboard)), which also knows
`vbKeyShift` (16) and `vbKeyMenu` (18) for either Shift or either Alt.

The Help key opens the program's help when `App.HelpFile` is set, at the `helpnode=` of the
control under the pointer, else of the window, else at `main`
([chapter 13](13-menus-dialogs.md#amigaguide-help)), and then the window gets no key events
for it; otherwise it is an ordinary key.

## Several forms

A project can have any number of forms, one `Form=` line each. One of them is the startup
form; the others are loaded when the program first uses them. `examples/book/ch12-forms/twoforms`
has a main window, a modal dialog and a small window beside it:

```ini
# TwoForms: a main window, a modal dialog and a tool window (manual chapter 12)
Name=TwoForms
Startup=Form people
Form=people.afg
Form=person.afg
Form=about.afg
```

The dialog's layout gives the window a name of its own, `dlgPerson`, so the main form's code
shows which is which: the form (`dlgPerson`) or its code-behind module (`person`). Naming the
window `person` would work too.

```text
# person.afg - a small modal dialog
window name=dlgPerson title="Person" width=240 height=0 toolwindow=1
vlayout id=root
  string id=nameField label="_Name" maxchars=40
  hlayout even=1
    button id=ok text="_OK" default=1
    button id=cancel text="_Cancel" cancel=1
```

Return clicks OK and Esc clicks Cancel while the cursor is not in the field; in the field,
Return arrives in `nameField_KeyPress`. Its code-behind leaves its answer in Public variables
and hides itself, which ends the modal `Show`:

*Listing 12.9* (`examples/book/ch12-forms/twoforms/twoforms.bbp`)

<!-- project: examples/book/ch12-forms/twoforms/twoforms.bbp -->
```basic
' person.bas - the dialog's code-behind; its Public variables are what it answers
Option Explicit

Public Accepted As Boolean
Public Answer As String

Private Sub Form_Load()
    Accepted = False
End Sub

Private Sub Form_Activate()
    nameField.SetFocus
End Sub

Private Sub nameField_KeyPress(KeyAscii As Integer)
    If KeyAscii = 13 Then ok_Click
End Sub

Private Sub ok_Click()
    If Trim(nameField.Text) = "" Then Beep: Exit Sub
    Answer = Trim(nameField.Text)
    Accepted = True
    Me.Hide                             ' ends Show vbModal
End Sub

Private Sub cancel_Click()
    Me.Hide
End Sub
```

The main form:

*Listing 12.10* (`examples/book/ch12-forms/twoforms/twoforms.bbp`)

<!-- project: examples/book/ch12-forms/twoforms/twoforms.bbp -->
```basic
' people.bas - the startup form
Option Explicit

Private Sub Form_Load()
    Debug.Print "people: Form_Load"
End Sub

Private Sub add_Click()
    If AskName("Add a person", "") Then names.AddItem person.Answer
End Sub

Private Sub edit_Click()
    If names.ListIndex < 0 Then MsgBox "Choose a name first", vbExclamation: Exit Sub
    If AskName("Change the name", names.Text) Then names.List(names.ListIndex) = person.Answer
End Sub

Private Sub names_DblClick()
    edit_Click
End Sub

' the dialog: set it up, show it modally, read what it left in its Public variables.
' dlgPerson is the form (the window name in person.afg), person its code-behind module.
Private Function AskName(ByVal title As String, ByVal start As String) As Boolean
    Load dlgPerson                      ' loads the form (Form_Load runs) without showing it
    dlgPerson.Caption = title
    dlgPerson.nameField.Text = start    ' a control of another form: form.control
    dlgPerson.Show vbModal              ' returns when the dialog is hidden or unloaded
    AskName = person.Accepted           ' a Public variable of the module person.bas
    Unload dlgPerson
End Function

Private Sub about_Click()
    aboutBox.Show                       ' not modal: both windows take input
End Sub

Private Sub Form_QueryUnload(Cancel As Integer, UnloadMode As Integer)
    If UnloadMode = 0 Then              ' the close gadget, not Unload in code
        If MsgBox("Quit?", vbOKCancel + vbQuestion) = vbCancel Then Cancel = True
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    Unload aboutBox                     ' the program ends when the last form is unloaded
End Sub
```

Points about several forms:

- **Modal and modeless.** `form.Show` opens a window beside the others, and your code goes on
  at once. `form.Show vbModal` waits: the other windows show a busy pointer and take no input
  until the form is hidden or unloaded, then `Show` returns. Timers keep running meanwhile.
  `vbModeless` (0) is the same as no argument.
- **Hide or Unload.** `Hide` keeps the form loaded, with everything typed into it, so the next
  `Show` is quick and shows the same values. `Unload` frees it, and the next use loads it
  again, running `Form_Load` again.
- **Ending the program.** The program ends when no form is loaded any more. A window that is
  only hidden still counts, so unload your other forms in the main form's `Form_Unload`, as
  above, or use `End`.
- **Only one copy of each form.** A form is a single object: you can't make two windows from
  one `.afg` with `New`. Make a second `.afg` for a second kind of window.
- There is no `Forms` collection listing the loaded forms, and no control arrays (several
  controls with one name and an index). Give controls numbered ids and reach them with
  `Me.Controls("b" & i)`.

### Sub Main instead of a startup form

With `Startup=Sub Main` a form program starts in `Sub Main`, which can do its own set-up and
then show a form. When `Sub Main` returns, the program ends and closes its windows, so show
the first form with `vbModal`. Here the form's window is named `mainWin` in its `.afg`, so
that a standard module can reach it:

<!-- fragment -->
```basic
Sub Main()
    If Command = "--help" Then Print "usage: people [file]": Exit Sub
    mainWin.Show vbModal                ' returns when the window is closed
End Sub
```

## Testing without a display

On macOS, Linux and other hosts there is no GUI. `boing check` checks form programs as usual,
but running one fails with "forms need AmigaOS 4". With the environment variable
`BOING_HEADLESS=1`, forms run without a window: the `.afg` is read, the controls keep their
properties, and events fire as they would (`Form_Load` while loading, `Activate` and `Resize`
on `Show`, `Click` and `Change` when code sets `ListIndex`, `Value` or `Text`, the
`QueryUnload` / `Unload` pair, timers in real time). The program ends when its last form is
unloaded, or after `BOING_HEADLESS_SECS` seconds (10 if not set):

```sh
$ BOING_HEADLESS=1 BOING_HEADLESS_SECS=2 boing run hello.bbp
```

Nobody clicks anything there, so this is for tests your program runs on itself, for example
from a Timer that fills in fields, clicks buttons by calling their `_Click` subs, prints what
it finds and unloads the form. Only the basic properties are kept without a display (texts,
values, list items, `Enabled`, `Visible`, `Tag`); `MsgBox` and `InputBox` ask on the console,
and the richer controls (grid, tree view, the text editor's methods, the CommonDialog) are not
there.

## Summary

- A form is an `.afg` layout plus its code-behind `.bas`, added to a project with
  `Form=file.afg`; `Startup=Form name` opens it first.
- The `.afg` has a `window` line, one root `vlayout` or `hlayout` with the controls indented
  under it, and the menus last. `weight`, `label`, `even`, `title` and `splitter` shape the
  layout.
- Controls are variables named by their `id`; events call `id_Event` subs, the form's own
  `Form_Event` subs. `Me` is the form.
- `Show`, `Show vbModal`, `Hide`, `Load` and `Unload` manage forms; `Form_QueryUnload` and
  `Form_Unload` can keep a form open; the program ends with its last form.
- The reference above lists every control's keys, properties, methods and events; key codes
  are in [The keyboard](#the-keyboard). A `_` letter in a text or label is a working shortcut
  (for fields, in their `label`; a `label` control's letter works the control after it),
  and `default=1` / `cancel=1` buttons take Return and Esc.
- `font`, `fontsize`, `screen`, `pubscreen`, `fullscreen` and `screentitle` on the `window`
  line choose the window's font and screen ([The AmigaOS 4 desktop](18-desktop.md)).

See also: [Using AmiForge](03-amiforge.md), [Menus, toolbars and dialogs](13-menus-dialogs.md),
[Graphics](14-graphics.md), [Classes and objects](11-classes.md).
