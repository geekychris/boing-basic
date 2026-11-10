# RegExp: regular expressions

`RegExp` finds, checks, extracts and replaces text by pattern: is this an e-mail address, pull
the dates out of a log, turn `2026-11-10` into `10.11.2026`. Boing BASIC has its own engine,
the same on AmigaOS 4 and the host, with the familiar pattern syntax.

```basic
Dim re As RegExp
Set re = CreateObject("RegExp")
re.Pattern = "(\d{4})-(\d\d)-(\d\d)"
re.Global = True
Print re.Replace("from 2026-11-10 to 2026-12-24", "$3.$2.$1")    ' from 10.11.2026 to 24.12.2026
If re.Test(line) Then Print "has a date"
```

## The RegExp object

| Member | |
|---|---|
| `Pattern` | the regular expression (default member) |
| `Global` | False (default): `Execute` and `Replace` stop at the first match. True: all matches. |
| `IgnoreCase` | match letters in either case (A-Z and the Latin-1 accented letters) |
| `MultiLine` | `^` and `$` also match at the start and end of every line, not only of the whole text |
| `Test(text)` | True if the pattern matches somewhere in text |
| `Execute(text)` | the matches, as a `Matches` collection (one match unless `Global`) |
| `Replace(text, replacement)` | text with the match (or with `Global` every match) replaced |
| `Split(text)` | an array of the pieces between matches (text of groups in the pattern is included) |
| `FirstMatch(text)` | the text of the first match, "" if none |
| `Escape(text)` | text with every special character (`\ ^ $ . \| ? * + ( ) [ ] { } -`) escaped, so it matches literally: `re.Pattern = re.Escape(userInput)` |

The pattern is compiled once and kept until `Pattern`, `IgnoreCase` or `MultiLine` changes, so
using one `RegExp` in a loop is fast.

## Matches, Match, SubMatches

`Execute` returns a `Matches` collection: `Count`, `Item(i)` (the default member, so `ms(0)`)
counting from 0, and `For Each`. Each item is a `Match`:

| Match member | |
|---|---|
| `Value` | the matched text (default member: `Print m`) |
| `FirstIndex` | where it starts, counting from **0** (add 1 for `Mid`) |
| `Length` | its length |
| `SubMatches` | the groups' texts: `m.SubMatches(0)` is group 1; `m.SubMatches.Count`; `For Each`. A group that didn't take part in the match is Empty. |
| `SubMatchIndex(i)` | where group i+1 matched (from 0), -1 if it didn't |

```basic
re.Pattern = "(\w+)@([\w.]+)"
re.Global = True
For Each m In re.Execute("write to ann@boing.org or bob@amiga.net")
    Print m.SubMatches(0); " at "; m.SubMatches(1); " (position"; m.FirstIndex; ")"
Next
```

## Pattern syntax

| | matches |
|---|---|
| `abc` | the characters themselves |
| `.` | any character except a line feed |
| `[abc]` `[a-z]` `[^0-9]` | one of the listed characters / a range / not these (`\d`, `\w`, `\s` work inside) |
| `\d` `\w` `\s` | a digit / a letter, digit or `_` / white space (space, tab, CR, LF, FF, VT) |
| `\D` `\W` `\S` | not a digit / word character / white space |
| `^` `$` | the start / end of the text (of each line with `MultiLine`) |
| `\b` `\B` | a word boundary / not a word boundary |
| `x*` `x+` `x?` | 0 or more / 1 or more / 0 or 1 of x, as many as possible |
| `x{n}` `x{n,}` `x{n,m}` | exactly n / at least n / n to m |
| `x*?` `x+?` `x??` `x{n,m}?` | the same, as few as possible ("lazy") |
| `a\|b` | a or b |
| `(x)` | a group: repeat it as a whole (`(ab)+`), and remember its text (`$1`, `SubMatches`, `\1`) |
| `(?:x)` | a group that isn't remembered |
| `x(?=y)` `x(?!y)` | x only if followed / not followed by y (y isn't part of the match) |
| `\1` ... `\9` | the text group 1-9 matched (`(\w)\1` finds a doubled letter) |
| `\n` `\t` `\r` `\f` `\v` `\0` | line feed, tab, CR, form feed, vertical tab, NUL |
| `\xHH` `\uHHHH` | a character by its hex code (up to 255) |
| `\.` `\*` `\\` ... | a special character itself |

Strings are bytes, so a pattern can find binary data (`\x00+`); text in Latin-1, as on the
Amiga, works with `IgnoreCase` for the accented letters too.

## Replacement text

In `Replace`, the replacement may contain:

| | inserts |
|---|---|
| `$1` ... `$99` | the text of a group ("" if it didn't take part) |
| `$&` | the whole match |
| ``$` `` | the text before the match |
| `$'` | the text after the match |
| `$$` | a `$` |

## Errors

| `Err.Number` | |
|---|---|
| 5017 | the pattern is wrong; `Err.Description` says what is wrong ("missing )", "nothing to repeat before *, + or ?"...) |
| 5019 | the pattern needs too much backtracking on this text (a pattern like `(x+x+)+y` can take practically forever; the engine gives up after 50 million steps) |
| 9 | `Item` / `SubMatches` index out of range |
| 383 | Matches and Match are read-only |

## Example: a log analyser

```basic
' count the error lines in a log ("12:01:33 [Http] error: ...") and list the programs
Dim re As RegExp, line As String, name As String, errors As Long, seen As String
Set re = CreateObject("RegExp")
re.Pattern = "^\d\d:\d\d:\d\d \[(\w+)\] error:"
re.IgnoreCase = True
Open "RAM:app.log" For Input As #1
Do Until EOF(1)
    Line Input #1, line
    If re.Test(line) Then
        errors = errors + 1
        name = re.Execute(line)(0).SubMatches(0)
        If InStr(seen, "|" & name & "|") = 0 Then seen = seen & "|" & name & "|"
    End If
Loop
Close #1
If errors = 0 Then Print "no errors" Else Print errors; " errors, from "; Replace(Mid(seen, 2, Len(seen) - 2), "||", ", ")
```

## How it works

A backtracking matcher: the pattern is compiled to a small program and tried at each position
of the text. Its stack is on the heap, so deep patterns don't overflow the AmigaOS stack, and
there is a limit on the number of steps instead of hanging. Searching for a pattern that starts
with a plain character skips to that character quickly.

## Tests

`tests/regexp/retest.bas` (part of `make test`; VM, JIT and native, and on the AmigaOS 4 guest
with `tools/os4guest.py bas tests/regexp/retest.bas both`): every syntax element, greedy and lazy
repetition, groups, backreferences, lookahead, the options, Execute/Matches/SubMatches, Replace
with all `$` forms, Split, Escape, binary data, a 200 KB text, every syntax error and the
backtracking limit.

## Not yet

Lookbehind `(?<=...)`, named groups, Unicode classes (strings are bytes).
