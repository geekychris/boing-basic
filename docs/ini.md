# IniFile: settings files

`IniFile` reads and writes INI files, the plain-text settings format with `[sections]` and
`key=value` lines. Use it for a program's preferences, a game's options or a tool's
configuration: the user can edit the file with any text editor, and `IniFile` keeps their
comments and layout when the program saves its changes.

```basic
Dim prefs As IniFile
Set prefs = CreateObject("IniFile")
prefs.Load "PROGDIR:Tincture.ini"                 ' a missing file is simply empty
width = CLng(prefs.Value("Window", "Width", "640"))
...
prefs.Value("Window", "Width") = Me.Width
prefs.Save
```

```ini
; Tincture settings
[Window]
Width=640
Height=480

[Recent]
File1=Work:Pictures/sunset.iff
```

## Reading

| Member | |
|---|---|
| `Load path [, mustExist]` | reads a file and remembers its name for `Save`. Returns True if it was there; a missing file gives an empty IniFile (error 53 instead with mustExist = True). |
| `LoadText text` | the same from a String |
| `Value(section, key [, default])` | a value as a String; default (or "") if the key or section isn't there. The default member: `prefs("Window", "Width")`. |
| `Sections` | the section names as an array (`""` first if there are keys before the first section) |
| `Keys(section)` | the key names of a section as an array (empty array: `UBound` = -1) |
| `HasSection(section)`, `HasKey(section, key)` | True if present |

Names of sections and keys are not case-sensitive. Spaces around keys and values are ignored;
put a value in double quotes to keep spaces at its ends (`Name="  x  "`). Lines starting with
`;` or `#` are comments. Keys before the first `[section]` belong to the section `""`.

## Changing and saving

| Member | |
|---|---|
| `Value(section, key) = value` | sets a value; adds the key (after the section's last key) or the section (at the end) if needed |
| `DeleteKey(section, key)` | removes a key; True if it was there |
| `DeleteSection(section)` | removes a section with all its keys and comments; True if it was there |
| `Clear` | empties everything |
| `Save [path]` | writes the file (to path, or where it was loaded from) |
| `Text` | the whole file as text; assigning it is `LoadText` |
| `Path` | the file name used by `Save` |
| `Changed` | True if something was changed since loading or saving |

Saving writes every line the program didn't change exactly as it was (comments, blank lines,
spacing, order). Files with CR LF line ends keep them. Values can't contain line breaks
(error 5); a key can't contain `=` or start with `[`, `;` or `#`.

Numbers are stored as text: read them with `CLng`/`CDbl`/`Val`, and a value assigned from a
number is written as `CStr` writes it.

## Errors

53 a missing file with mustExist, 75 the file can't be created, 61 writing failed, 5 a bad key
or value, or `Save` without a file name.

## IniFile or GetSetting?

`GetSetting`/`SaveSetting` keep each value in its own small file in the system's settings
drawer (`ENVARC:`), which the user doesn't usually edit. An `IniFile` is one readable file
wherever you put it (next to the program, in `ENVARC:`, on a USB stick).

## Tests

`tests/libs/initest.bas` (VM, JIT and native in `make test`; on the AmigaOS 4 guest with
`tools/os4guest.py bas tests/libs/initest.bas both`).
