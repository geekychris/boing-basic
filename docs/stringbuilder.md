# StringBuilder: building long texts fast

`s = s & piece` copies the whole of `s` every time, so building a text from thousands of pieces
gets slower and slower. A `StringBuilder` adds pieces to a growing buffer instead.

```basic
Dim sb As StringBuilder
Set sb = CreateObject("StringBuilder")
For i = 1 To 10000
    sb.Append "line "
    sb.AppendLine CStr(i)
Next
page.Text = sb.ToString          ' or just sb: ToString is the default member
```

20,000 appends of 5 characters: `s = s & x` 2.30 s, `StringBuilder` 0.02 s (interpreter, AmigaOS 4
on QEMU); 200,000 appends on the host: 1.4 s against 0.005 s.

| Member | |
|---|---|
| `Append x [, y ...]` | adds the text of each argument (numbers, Booleans... as `CStr` writes them); returns the builder, so `sb.Append("a").Append("b")` works |
| `AppendLine [x]` | adds `x` and a line feed (`vbLf`) |
| `Insert pos, x` | inserts at position `pos` (1 = the start, `Length + 1` = the end) |
| `Remove start, count` | removes `count` characters from `start` |
| `Replace(find, with)` | replaces every occurrence (case-sensitive); returns how many |
| `Clear` | empties it (keeps the memory) |
| `ToString` | the text (default member) |
| `Length` | the number of characters; setting it shortens the text or pads it with spaces |
| `Capacity` | the buffer size; setting it reserves at least that much room in advance (it is rounded up, so reading it back can give more) |
| `Char(pos)` | one character; `sb.Char(pos) = "x"` changes it (exactly one character: anything else is error 5) |

Positions out of range raise error 5. Like Strings, a StringBuilder holds bytes, so binary data
is fine.

## Tests

`tests/lib/sbtest.bas` (in `make test`, VM and native): every member, chaining, padding,
binary data, 100,000 appends, the errors. On the AmigaOS 4 guest: identical output in the VM and
native.
