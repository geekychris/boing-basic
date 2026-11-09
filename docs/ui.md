# Application UI: menus, toolbars, dialogs, rich controls, Workbench, ARexx

What a "best of breed" AmigaOS 4.1 application needs beyond the basic controls of
[forms-events.md](forms-events.md): this file is the plan and the reference for it. Each
section says its status: **done** (in main, tested on the guest), **in progress** or
**planned**. The control/event contract the IDE reads stays [forms-events.md](forms-events.md);
everything marked done here is listed there too.

Conventions are VB6's where VB6 has the feature (names, events, constants), AmigaOS's where
it doesn't (patterns `#?.txt`, Amiga-key shortcuts, ENV: preferences, tooltypes). Strings are
Latin-1. Everything works the same from `boing run` (VM), the JIT and native builds: the
members are late bound (see runtime-api.md, "Forms").

New `.afg` kinds: `menu`, `toolbar`, `tool`, `statusbar`, `commondialog`, `tabs`, `treeview`,
`grid`, `image`. New properties on existing kinds are listed per section.

## 1. Menus

A form's menu bar is a tree of `menu` objects at the top level of the `.afg`, after the root
layout (VB's Menu Editor: every title, item and sub-item is a `Menu` control):

```
window name=main title="Paint" width=400 height=300
vlayout id=root
  canvas id=view width=320 height=200 contextmenu=mnuCanvas
menu id=mnuFile text="Project"
  menu id=mnuNew text="New" key=N
  menu id=mnuOpen text="Open..." key=O
  menu text=-
  menu id=mnuRecent text="Open recent"
    menu id=mnuRecent0 text="(empty)" disabled=1
  menu text=-
  menu id=mnuQuit text="Quit" key=Q
menu id=mnuView text="View"
  menu id=mnuGrid text="Grid" checkable=1 checked=1 key=G
  menu text=-
  menu id=mnuZoom1 text="Zoom 100%" radio=1 checked=1
  menu id=mnuZoom2 text="Zoom 200%" radio=1
menu id=mnuCanvas text="Canvas" hidden=1
  menu id=mnuClear text="Clear"
```

| .afg key | meaning |
|---|---|
| `text` | the caption; `-` is a separator bar |
| `key` | the Amiga-key shortcut (one character: right-Amiga + key, handled by Intuition). Longer strings (`"Ctrl Z"`) are shown at the right of the item; the program handles those keys itself in `Form_KeyDown` |
| `checkable` | a toggle item with a checkmark |
| `checked` | initial state of a checkable or radio item |
| `radio` | mutually exclusive with the other `radio` items of the same panel |
| `disabled` | greyed out (a title disables its whole menu) |
| `hidden` | not shown; a hidden top-level menu is a pop-up / context menu (VB's trick for `PopupMenu`) |
| `image` | a picture file (any datatype) shown at the left of the item |

| Property | Type | Notes |
|---|---|---|
| `Caption` | String | |
| `Checked` | Boolean | for any item; setting it on a plain item makes it checkable |
| `Enabled` | Boolean | |
| `Visible` | Boolean | |
| `Shortcut` | String | the `key` |
| `Tag`, `Name` | String | |

| Event | Signature | When |
|---|---|---|
| `Click` | `<id>_Click()` | the item was chosen (with the mouse, its shortcut, or from a context menu). A checkable item has its new `Checked` state already |

The form's methods for menus:

| Method | Notes |
|---|---|
| `Me.PopupMenu menu [, x, y]` | opens the (hidden) top-level `menu` as a pop-up at the pointer, or at x, y inside the window; returns after the user chose (the item's `Click` comes first) or cancelled. `menu` is the menu control or its name |
| `Me.AddMenu id, caption [, parent [, key]]` | adds a menu at run time (no `parent` = a new title at the end); its `<id>_Click` sub is called as for designed menus |
| `Me.RemoveMenu id` | removes a menu added at run time, or a designed one, with its sub-items |
| `Me.Controls(name)` | any control by name (also menus added at run time) |

**Context menus**: `contextmenu=<menu id>` on any control (or on the window) names a hidden
top-level menu that the right mouse button opens over that control, the OS4 way
(`WA_ContextMenuHook`). At run time `ctl.ContextMenu = "mnuCanvas"` (or `""` to remove).
`Me.ContextControl` is the name of the control the last context menu was opened over.

Style guide notes: put Quit last in the first menu with `key=Q`, About in it too; use `...`
for items that open a requester.

Status: **done** (tests/os4/ui_menu_test.c: shortcuts, checkable and radio items, Enabled,
AddMenu/RemoveMenu, a context menu with the right mouse button; 25/25 on the m1 guest).
`PopupMenu` uses popupmenu.class; `image=` on items is not done yet.

## 2. Toolbars and status bars

```
toolbar id=tb
  tool id=tbNew text="New" image="PROGDIR:images/new.png" hint="New picture"
  tool id=tbOpen text="Open" image="PROGDIR:images/open.png"
  tool separator=1
  tool id=tbGrid text="Grid" image="PROGDIR:images/grid.png" toggle=1 checked=1
statusbar id=sb panels="Ready|Ln 1|100%" widths="0|60|50"
```

`toolbar` is a row of buttons (speedbar.gadget); each `tool` is a control of its own with a
`Click` event (`tbNew_Click()`), `Enabled`, `Value` (toggle tools: 0/1), `ToolTipText` and
`Picture` (the image file). The images are loaded with bitmap.image (datatypes: PNG, IFF,
...); `selimage=` gives a separate pressed image. Without an image the text is shown;
`textonly=1` / `imagesonly=1` on the toolbar force one style. Tools with the same `menu` id
behave like that menu item: `tool id=tbOpen menu=mnuOpen` calls `mnuOpen_Click` and follows
its `Enabled`.

`statusbar` is a row of recessed text panels. `widths` are pixel widths, 0 = takes the rest.

| Property | Type | Notes |
|---|---|---|
| `Text` / `SimpleText` | String | panel 0 |
| `Panel(i)` | String | panel i's text (get/set) |
| `PanelCount` | Long, R/O | |

`toolbar` has `ButtonCount` (R/O, separators included) and the common properties
(`Enabled`, `Visible`, ...). Tools can't be hidden (speedbar.gadget has no hidden buttons):
`Visible` on a tool is only remembered.

Status: **done** (tests/os4/ui_bars_test.c 25/25 on the local guest; tests-os4/uibas).

## 3. Standard dialogs: `commondialog` (VB `CommonDialog`)

Put a `commondialog id=dlg` anywhere in the layout (it takes no space, like `timer`), or create
one in code: `Set dlg = CreateObject("Boing.CommonDialog")`.

| Method | Requester |
|---|---|
| `ShowOpen` | asl file requester for loading |
| `ShowSave` | asl file requester for saving (overwrite prompt with `cdlOFNOverwritePrompt`) |
| `ShowFont` | asl font requester |
| `ShowScreenMode` | asl screen mode requester |
| `ShowColor` | a colour requester (palette + RGB sliders) |
| `ShowPalette` | edit a palette of up to 256 colours (`Colors(i)`, `ColorCount`) |
| `ShowMessage(prompt, buttons [, title [, icon]])` | a requester with your own buttons (`"_Save\|_Discard\|_Cancel"`); returns the 1-based number of the button chosen (Esc / close = the last button) |

| Property | Type | Notes |
|---|---|---|
| `DialogTitle` | String | |
| `FileName` | String | the full path chosen (first file with multi-select) |
| `FileTitle` | String | the file part only |
| `InitDir` | String | the starting drawer |
| `Filter` | String | an AmigaDOS pattern `#?.(iff\|png)`; VB style `"Pictures\|#?.png"` also works (the text before `\|` is ignored) |
| `Flags` | Long | `cdlOFNAllowMultiselect` (&H200), `cdlOFNOverwritePrompt` (&H2), `cdlOFNFileMustExist` (&H1000), `cdlOFNPathMustExist` (&H800), `cdlOFNNoChangeDir`; `cdlCFEffects` for fonts (style buttons) |
| `FileCount` | Long, R/O | number of files chosen (multi-select) |
| `Files(i)` | String, R/O | full path of file i (0-based) |
| `CancelError` | Boolean | `True`: cancelling raises error 32755 (`cdlCancel`), as VB |
| `Cancelled` | Boolean, R/O | the last Show* was cancelled (simpler than CancelError) |
| `FontName`, `FontSize`, `FontBold`, `FontItalic`, `FontUnderline` | | the font (FontName as `"DejaVu Sans Mono"`, without `.font`) |
| `Color` | Long | VB colour (`RGB()`) |
| `Colors(i)`, `ColorCount` | Long | ShowPalette |
| `ScreenModeID`, `ScreenWidth`, `ScreenHeight`, `ScreenDepth` | Long | ShowScreenMode |

Requesters open on the form's screen, centred on the active window, and block the form's
windows (busy pointer) while open.

Also on the App object: `App.Request(prompt, "_Save|_Discard|_Cancel" [, title [, icon]])`, the
same requester without a CommonDialog.

Status: **done**: ShowOpen/ShowSave (multi-select, patterns, overwrite prompt, CancelError),
ShowFont, ShowScreenMode, ShowColor, ShowMessage, CreateObject("Boing.CommonDialog")
(tests/os4/ui_bars_test.c, tests-os4/uibas). `ShowPalette` is **not done** (the
`Colors(i)`/`ColorCount` properties exist).

## 4. Richer controls

### TextEditor (`texteditor`), additions

| Property / method | Notes |
|---|---|
| `SelStart`, `SelLength`, `SelText` | the cursor / selection (characters from the start) |
| `CurrentLine`, `CurrentColumn` | 0-based cursor position |
| `Modified` | Boolean: changed since loaded or since set to False |
| `FixedFont`, `WordWrap`, `TabSize`, `Locked` | |
| `Bold`, `Italic`, `Underline` | style at the cursor / of the selection (texteditor.gadget soft styles) |
| `Cut`, `Copy`, `Paste`, `SelectAll`, `Undo`, `Redo`, `Clear` | methods |
| `InsertText s` | at the cursor |
| `Find(text [, matchCase])` | selects the next match; returns True if found |
| `Replace find, with [, all]` | |
| `LoadFile path`, `SaveFile path` | |

Event `<id>_Change()`; `<id>_CursorMove()` when the cursor moves (status bars).

### ListBrowser (`listbrowser`) columns, sorting, multiple selection

```
listbrowser id=files columns="Name|Size|Date" widths="60|20|20" sortable=1 multiselect=1
```

Rows with columns are added with the columns separated by tabs:
`files.AddItem "readme" & vbTab & "1024" & vbTab & "2026-11-08"`.

| Property / method | Notes |
|---|---|
| `ColumnCount` | R/O |
| `Cell(row, col)` | get/set one cell |
| `ColumnTitle(col)` | |
| `Selected(i)` | Boolean, multi-select state of row i |
| `SelCount` | R/O |
| `SortColumn`, `SortOrder` | 0 ascending, 1 descending; setting sorts |
| `Sort [col [, order]]` | method |
| `ItemData(i)` | Long kept with the row (moves with it when sorted) |

Events `Click`, `DblClick`, `<id>_ColumnClick(Column As Integer)` (a click on a column title;
with `sortable=1` the list sorts itself first).

### TreeView (`treeview`) — a hierarchical listbrowser

| Method / property | Notes |
|---|---|
| `AddNode key, parent, text` | parent `""` = a root node |
| `RemoveNode key`, `Clear` | |
| `Expand key`, `Collapse key` | |
| `NodeText(key)` | get/set |
| `NodeParent(key)`, `NodeCount` | |
| `SelectedKey` | get/set |

Events `<id>_NodeClick()`, `DblClick`, `<id>_Expand()` / `<id>_Collapse()`
(`SelectedKey` / `EventKey` say which node).

### Grid (`grid`) — an editable cell grid (VB `MSFlexGrid`), for spreadsheets

```
grid id=sheet rows=100 cols=26 fixedrows=1 fixedcols=1 colwidth=64 editable=1
```

Drawn by the runtime with graphics.library into its own area (only the cells that change
are redrawn), with ReAction scrollers.

| Property / method | Notes |
|---|---|
| `Rows`, `Cols`, `FixedRows`, `FixedCols` | |
| `Row`, `Col` | the current cell |
| `TextMatrix(row, col)` | get/set any cell |
| `Text` | the current cell |
| `ColWidth(col)`, `RowHeight` | pixels |
| `TopRow`, `LeftCol` | scrolling |
| `ColAlignment(col)` | 0 left, 1 right, 2 centre |
| `CellBold(row, col)`, `CellForeColor(row, col)`, `CellBackColor(row, col)` | |
| `SelStartRow`, `SelStartCol`, `SelEndRow`, `SelEndCol` | the selected range |
| `Editable` | Boolean |
| `Redraw` | Boolean: False while filling many cells |

Events `<id>_EnterCell()`, `<id>_LeaveCell()`, `<id>_BeforeEdit(Cancel As Integer)`,
`<id>_AfterEdit()`, `Click`, `DblClick`, `<id>_KeyDown(KeyCode As Integer, Shift As Integer)`.
Typing on a cell starts editing, Return/Tab/cursor keys end it.

### Tabs (`tabs`) — clicktab.gadget with pages

```
tabs id=pages
  vlayout title="General"
    ...
  vlayout title="Advanced"
    ...
```

Each child layout is a page; its `title` is the tab's label. `Tab` (0-based, get/set),
`TabCount`, `TabCaption(i)`; event `Click` when the user changes the tab.

### Splitter

`hlayout splitter=1` / `vlayout splitter=1`: the user can drag the bars between the children
to resize them (layout.gadget weight bars).

### Images and bitmap buttons

`image id=logo file="PROGDIR:logo.png"`: a picture (bitmap.image); `Picture` sets another
file. `button image="PROGDIR:icons/save.png" text="Save"`: a button with a picture (and text
below it, or only the picture with `text=""`).

### Canvas: mouse events and scrolling

Canvases (graphics.md) get mouse events: `<id>_MouseDown(Button As Integer, Shift As Integer,
X As Long, Y As Long)`, `<id>_MouseUp(...)`, `<id>_MouseMove(...)` (only while a button is
down, unless `mousemove=1`), `<id>_DblClick()`, `<id>_MouseWheel(Delta As Integer)`. X, Y are
in canvas pixels. A canvas with `scrollbars=1` gets scrollers for a picture larger than the
view (`ScrollX`, `ScrollY`, `VirtualWidth`, `VirtualHeight`; event `<id>_Scroll()`).

### Progress (`fuelgauge`) additions

`Text` (a label in the gauge instead of the percentage), `ShowPercent`.

Status: **done** (tests/os4/ui_controls_test.c 35/35 on the local guest, ui_mouse_test 7/7):
canvas mouse events, TextEditor, ListBrowser columns/sorting/multi-select, tabs, TreeView, Grid,
splitter, images and picture buttons. **Not done**: canvas `scrollbars=1` (use scroller
controls beside it for now), fuelgauge `Text`/`ShowPercent`.

## 5. Multiple windows, modal dialogs, tool windows

| | |
|---|---|
| `frm.Show vbModal` | shows the form and returns when it is hidden or unloaded; the other windows get a busy pointer and no input meanwhile (VB `vbModal` = 1); timers keep running (a timer whose own event opened the modal form waits, as events never overlap) |
| `toolwindow=1` (.afg) | a tool window: no size or depth gadget |
| `remember=1` (.afg) | the window's position and size are saved in `ENV:` and `ENVARC:<App.Title>/windows/<form>` when it closes and used when it opens |
| `iconify=1` (.afg) | an iconify gadget; `WindowState = 1` iconifies from code, `0` opens it again; `Form_Resize` follows both |

Status: **done** (tests/os4/ui_forms2_test.c 9/9 on the local guest). **Not done**: the
`Forms` collection, `Me.ActiveControl`, an owner for `Show vbModeless, owner`.

## 6. Workbench integration

| | |
|---|---|
| `App.ToolType("NAME" [, default])` | a tooltype of the program's icon (`NAME=value` → `value`; a bare `NAME` → `"1"`; absent → default or `""`) |
| `App.ToolTypeCount`, `App.ToolTypes(i)` | the raw tooltype lines |
| `App.FromWorkbench` | Boolean |
| `App.ArgCount`, `App.Arg(i)` | the files given to the program (Workbench multi-select / project icons, or the command line) |
| `Me.OLEDropMode = 1` / `dropfiles=1` | the form is an AppWindow: files dropped on it fire `Form_OLEDragDrop(Count As Integer, X As Integer, Y As Integer)` or, over a control with `dropfiles=1`, `<id>_OLEDragDrop(...)`; `App.DropFile(i)` (full paths) |
| `App.ShowAppIcon name [, iconfile]` / `App.HideAppIcon` | an AppIcon on the Workbench: `AppIcon_DblClick()`, `AppIcon_DragDrop(Count As Integer)` |
| `App.AddAppMenuItem(text)` | a Workbench Tools menu item; returns its index; `AppMenu_Click(Index As Integer, Count As Integer)` (files selected in Workbench: `App.DropFile(i)`) |
| `Clipboard.GetText` / `SetText` | (exists) |
| `Clipboard.SetPicture canvas` / `Clipboard.GetPicture canvas` | IFF ILBM on the clipboard (24-bit, or 8-bit with a palette); `Clipboard.HasPicture` |
| `App.SaveIcon path [, defaultTool [, template]]` | writes `path.info`: a project icon (the template's image, else the default project icon) whose default tool is this program (or `defaultTool`) |

Workbench event subs (`AppIcon_*`, `AppMenu_*`, `ARexx_*`) can be in any module; the startup
form's code-behind is looked at first. The ports are served by the forms event loop, and by
`DoEvents` in programs without forms.

Status: **done** for ToolType/ToolTypes/ToolTypeCount, FromWorkbench, ArgCount/Arg, SaveIcon,
Clipboard.SetPicture/GetPicture/HasPicture (tested in tests-os4/uibas); AppWindow drops,
AppIcon and AppMenuItem are implemented but not yet tested on the guest (they need a
Workbench drag, which the tests can't do yet).

## 7. ARexx, preferences, locale, help

### ARexx port

```basic
App.ARexxPort = "BOINGPAINT"          ' opens the port (arexx.class); BOINGPAINT.1 if taken

Sub ARexx_Command(Cmd As String, Args As String, Result As String)
    Select Case UCase(Cmd)
    Case "OPEN": LoadPicture Args: Result = "OK"
    Case "VERSION": Result = App.Title & " 1.0"
    Case Else: App.ARexxRC = 5         ' an error for the caller (RC)
    End Select
End Sub
```

`Cmd` is the first word, `Args` the rest of the line. Don't start an ARexx script that talks
to your own port with `Shell` (it waits for `rx`, and `rx` waits for your program): use
`App.RunARexx`. `Result` goes back as `RESULT` (with
`OPTIONS RESULTS`), `App.ARexxRC` (default 0) as `RC`. `App.ARexxPortName` is the name actually
used. Sending: `r = App.SendARexx("PORT", "command args")` (returns `RESULT`, `App.ARexxRC` the
RC; error 5 if there is no such port); `App.RunARexx "script.rexx"` runs a script (async).

### Preferences: `GetSetting` / `SaveSetting` / `DeleteSetting` (VB)

`SaveSetting appname, section, key, value` writes `ENVARC:<appname>/<section>/<key>` and
`ENV:...` (so the setting survives a reboot); `GetSetting(appname, section, key [, default])`
reads ENV:, then ENVARC:. `DeleteSetting appname, section [, key]`.
`App.EnvPath` is `ENVARC:<App.Title>` for files of your own.

### Locale catalogs

`App.OpenCatalog "paint.catalog" [, builtinLanguage]` opens the catalog (locale.library) for
the user's languages; `App.Str(id, "default")` returns the translated string for `id`, or the
default. Menus and controls can use `$id:default` texts in the `.afg` (e.g.
`text="$12:Open..."`): looked up when the form loads, so a translated catalog changes the GUI.
`App.Language` is the language in use.

### AmigaGuide help

`App.ShowHelp "PROGDIR:Paint.guide" [, "node"]` opens the help (amigaguide.library,
asynchronously); `App.HelpFile = "..."` makes the Help key open it at its `main` node.

Status: **done**: the ARexx port and SendARexx/RunARexx, GetSetting/SaveSetting/DeleteSetting
(tests/runtime/settings.bas on the host; ENV: on the guest in tests-os4/uibas), App.Str and
`$id:` texts without a catalog. OpenCatalog with a real catalog and ShowHelp are implemented
but not yet tested on the guest.

## 8. Printing (if time permits)

`Printer.Print text`, `Printer.Write text` (no new line), `Printer.NewPage`, `Printer.EndDoc`,
`Printer.KillDoc` (printer.device, text through the printer driver),
`Printer.PaintPicture canvas [, x, y, w, h]` (a graphic dump of a canvas through
`DRPA_SourceHook`), `Printer.ShowSetup` (printer.device's preferences requester),
`Printer.Page`.

Status: implemented, **not tested** (no printer on the guests).

## How it is built

- Late-bound members: control and form members are names handed to `bb_ctl_get/set/call`
  (forms_rt.c, bb_forms.h), so new members need no compiler change. `App.X`, `Clipboard.X` and
  `Printer.X` members that are not compiler built-ins go to a runtime object (`App` is an
  object of class `App`, ui_app.c).
- `src/runtime/os4/forms.c` (form, layout, existing controls), `src/runtime/os4/ui_*.c` for the
  new pieces (menus, toolbar, dialogs, grid, tree, Workbench, ARexx).
- The posix build has stubs (no GUI): dialogs return "cancelled", `GetSetting`/`SaveSetting`
  work on files under `$HOME/.boing/`.
