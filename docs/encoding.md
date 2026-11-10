# Text encodings: UTF-8, Base64, URL, hex

Functions for moving text and binary data between the Amiga and the rest of the world.

| Function | |
|---|---|
| `Utf8Encode(s)` | Latin-1 text (the Amiga's character set) → UTF-8 bytes |
| `Utf8Decode(s [, replacement])` | UTF-8 bytes → Latin-1 text; characters Latin-1 doesn't have, and invalid bytes, become `replacement` (default `"?"`; `""` drops them) |
| `Base64Encode(s [, lineLength])` | bytes → Base64 text; `lineLength` (e.g. 76 for e-mail) breaks lines with CR LF, 0 (default) doesn't |
| `Base64Decode(s)` | Base64 text → bytes; spaces and line breaks are ignored, the URL-safe alphabet (`-` and `_`) is accepted |
| `UrlEncode(s)` | percent-encoding for URLs and form data: letters, digits and `- _ . ~` stay, everything else becomes `%XX` (space is `%20`) |
| `UrlDecode(s)` | `%XX` → the byte, `+` → space |
| `HexEncode(s)` | bytes → hex digits (`"Boing!"` → `"426F696E6721"`) |
| `HexDecode(s)` | hex digits → bytes; spaces, line breaks and `:` between digits are ignored |

Boing BASIC Strings hold bytes, so all of these work on binary data as well as text.

## Why UTF-8 matters

The web, JSON and most files from other computers are UTF-8, where letters beyond plain ASCII
take two to four bytes. The Amiga (and Boing BASIC on it) uses Latin-1, one byte per letter. Text
read from the web shows `CafÃ©` where `Café` was meant until it is decoded:

```basic
page = web.Get("https://example.com/menu")
menu.Text = Utf8Decode(page)                         ' for display in a form
reply = web.Post(url, Utf8Encode(nameField.Text), "text/plain; charset=utf-8")
```

Characters Latin-1 doesn't have (€, emoji, Greek, ...) can't be shown on the Amiga's Latin-1
screens; they become the replacement text: `Utf8Decode(s, "?")`.

## Examples

```basic
' HTTP Basic authentication
web.SetHeader "Authorization", "Basic " & Base64Encode(user & ":" & password)

' a query string
url = "https://api.example.com/search?q=" & UrlEncode(Utf8Encode(searchText))

' form fields from a POST body ("name=Boing+BASIC&year=1985")
For Each pair In Split(body, "&")
    kv = Split(pair, "=")
    fields(UrlDecode(kv(0))) = UrlDecode(kv(1))
Next

' binary data in JSON or a text file
Print HexEncode(Left(fileData, 16))
```

## Errors

The decoders raise error **31301** for input that isn't valid, saying what and where:
`Base64: a character that isn't Base64 at character 5`, `URL: '%' isn't followed by two hex
digits at character 4`, `hex: an odd number of digits at character 3`. `Utf8Decode` never raises:
bytes that aren't valid UTF-8 become the replacement.

## Tests

`tests/lib/enctest.bas` (in `make test`, VM and native): Latin-1 ↔ UTF-8 for all 256 byte
values, characters beyond Latin-1, invalid and overlong sequences, the RFC 4648 Base64 vectors,
line breaks, the URL-safe alphabet, URL and hex round trips over all bytes, every error. On the
AmigaOS 4 guest: identical output in the VM and native (`tools/os4guest.py outtest
tests/lib/enctest.bas`).
