# Modern libraries

Programs today juggle data that comes from the internet and goes back to it: lookups by name,
JSON documents, text in UTF-8, checksums and signatures, dates in UTC. This chapter describes
the libraries Boing BASIC has for them, and for everyday jobs such as pattern matching, CSV
files, settings files, logging and running other programs. They are part of the runtime, so they work the same in
the interpreter and in native programs, on AmigaOS 4 and on macOS and Linux:

| Library | What it is for |
|---|---|
| [Dictionary](#dictionary) | a table of values looked up by key |
| [JSON](#json) | reading and writing JSON text |
| [Text encodings](#text-encodings) | UTF-8, Base64, URL and hex encoding |
| [Checksums and hashes](#checksums-and-hashes) | CRC32, MD5, SHA-1, SHA-256 and HMAC signatures |
| [Dates and times in UTC](#dates-and-times-in-utc) | UTC, Unix time and ISO 8601 dates |
| [StringBuilder](#stringbuilder) | building long strings quickly |
| [Regular expressions](#regular-expressions-regexp) | matching and replacing text by patterns |
| [CSV files](#csv-files-csv) | reading and writing comma-separated files |
| [Unique identifiers](#unique-identifiers-createuuid) | random unique IDs |
| [Running commands](#running-commands-process) | running Shell commands and capturing their output |
| [Settings files](#inifile-settings-files) | reading and writing INI files, keeping their comments |
| [Logging](#logger-logging) | log messages with levels, to the console or rotating files |
| [XML](#xmldocument-reading-and-writing-xml) | reading, changing and writing XML documents |
| [Compression and Zip archives](#compression-and-zip-archives) | gzip/zlib compression and .zip archives |
| [SQL databases](#sql-databases-sqlite) | tables, queries and transactions in a database file (SQLite) |

SQLite is the one exception to "part of the runtime": it is a standard extension, which a
project asks for with `Extension=sqlite` (see [SQL databases](#sql-databases-sqlite)).

Each library's classes are created with `New` or `CreateObject` like the runtime's other
objects; its functions are called like built-in functions. One rule applies to all of them:
names in Boing BASIC aren't case-sensitive, so a variable named like a class hides it: don't call
a variable `stringbuilder` or `csv`. (A module named like a class, such as a program
`dictionary.bas`, is fine: after `As` and `New` the name still means the class.)

## Dictionary

A `Dictionary` keeps values under keys: a price under a product name, a count under a word, a
setting under its name, a window under its title. You give it a key and it gives you the value
back at once, however many entries it holds, so you don't have to search through an array.
The entries stay in the order you added them, which makes the output of a program predictable.

A Dictionary is also what `JsonParse` gives you for a JSON object (see [JSON](#json) below),
so it is the natural way to hold data that comes from the web.

*Listing 20.1* (`examples/book/ch20-libraries/listing-20-01.bas`)

<!-- run -->
```basic
Option Explicit
Dim stock As Dictionary, item As Variant
Set stock = CreateObject("Dictionary")
stock("apples") = 12                    ' adds the key "apples"
stock("pears") = 7
stock("apples") = stock("apples") - 2   ' changes its value
Print stock("apples"); stock.Count
For Each item In stock
    Print item; ": "; stock(item)
Next
```

```output
 10  2 
apples:  10 
pears:  7 
```

### Making one

`Dictionary` is a class built into Boing BASIC. Declare a variable of its type and create the
object with `CreateObject`:

*Listing 20.2* (`examples/book/ch20-libraries/listing-20-02.bas`)

```basic
Dim prices As Dictionary
Set prices = CreateObject("Dictionary")    ' CreateObject("Boing.Dictionary") works too
```

`New Dictionary` is not accepted: the compiler stops with "use CreateObject("Boing.Dictionary")
to make a Dictionary". A `Dim d As Dictionary` lets the compiler check the member names you use
(`d.Coutn` is an error when you compile) and lets AmiForge complete them; `Dim d As Variant`
or `As Object` work as well, without those checks.

Like every object, a Dictionary is a reference: `Set copy = prices` gives a second name for the
same Dictionary, not a copy of it.

### Keys

A key is a **String**, a **number** or an **object**:

- Strings are compared exactly: `"Amiga"` and `"amiga"` are two keys, unless you set
  `CompareMode` to 1 (below).
- Numbers are compared by their value, whatever their type: `1`, `1&`, `1#` and `1.0` are one
  key. `True` is the number -1, so `d(True)` and `d(-1)` are the same entry too.
- A number and a string are never the same key: `d(1)` and `d("1")` are two entries. Values
  read from a file or a text field are Strings, so convert them (`CLng`, `Val`) first if your
  keys are numbers.
- An object is a key by identity: two different objects are two keys even if they hold the
  same things, and the same object is always the same key.
- `Empty` is a valid key (one key). `Null` and arrays are not: they raise error 5.

Values can be anything: numbers, Strings, Dates, arrays, objects, other Dictionaries.

### Members

| Member | Kind | What it does |
|---|---|---|
| `Item(key)` | property | the value stored under `key`. It is the default member, so `d(key)` means `d.Item(key)`. Reading a key that isn't there gives `Empty` and does not add it. Assigning adds the key, or replaces the value if it is there; use `Set d(key) = obj` to store an object |
| `Add key, value` | method | adds a new entry; error 457 if the key is already there |
| `Exists(key)` | method | `True` if the key is there |
| `Remove key` | method | removes the entry; error 5 if the key isn't there |
| `RemoveAll` | method | removes every entry |
| `Count` | property | the number of entries (read-only) |
| `Keys()` | method | the keys as an array of Variants, `0` to `Count - 1`, in the order they were added |
| `Items()` | method | the values as an array, in the same order |
| `Key(old) = new` | property | renames a key: its value and its place stay; error 5 if `old` isn't there, 457 if `new` is |
| `CompareMode` | property | 0 (the default): String keys are case-sensitive. 1: they aren't. Error 5 if you change it while the Dictionary has entries, error 380 for other values |

`For Each k In d` goes through the **keys**, in the order they were added. Read the value with
`d(k)`. Don't add or remove entries inside such a loop; when you need to, loop over a copy of
the keys: `For Each k In d.Keys`.

An empty Dictionary's `Keys` and `Items` are empty arrays: `UBound` gives -1, and a
`For i = 0 To UBound(a)` loop runs no times.

### Adding, reading and removing

Assigning with `d(key) = value` is the usual way to add. `Add` is stricter: it refuses a key
that is already there, which catches a duplicate you didn't expect.

*Listing 20.3* (`examples/book/ch20-libraries/listing-20-03.bas`)

<!-- run -->
```basic
Option Explicit
Dim d As Dictionary, k As Variant, keys As Variant, values As Variant

Set d = CreateObject("Dictionary")
d.Add "A500", 1987
d.Add "A1200", 1992
d("A4000") = 1992
d("CD32") = 1993

Print d.Exists("A1200"), d.Exists("A600")
Print IsEmpty(d("A600")), d.Count         ' reading a missing key doesn't add it

d.Remove "CD32"
d.Key("A500") = "Amiga 500"               ' renamed, still in the first place

keys = d.Keys
values = d.Items
Print UBound(keys) + 1; "models, first: " & keys(0) & " (" & values(0) & ")"
For Each k In d
    Print k, d(k)
Next
d.RemoveAll
Print d.Count
```

```output
True          False
True           4 
 3 models, first: Amiga 500 (1987)
Amiga 500      1987 
A1200          1992 
A4000          1992 
 0 
```

### Counting things

Reading a missing key gives `Empty`, and `Empty + 1` is 1, so counting needs no special first
case:

*Listing 20.4* (`examples/book/ch20-libraries/listing-20-04.bas`)

<!-- run -->
```basic
Option Explicit
Dim counts As Dictionary, w As Variant
Set counts = CreateObject("Dictionary")
For Each w In Split("red green red blue red green", " ")
    counts(w) = counts(w) + 1
Next
For Each w In counts
    Print w; " x"; counts(w)
Next
```

```output
red x 3 
green x 2 
blue x 1 
```

### Case-insensitive keys

Set `CompareMode = 1` while the Dictionary is still empty, and `"Red"`, `"RED"` and `"red"` find
the same entry. The key keeps the spelling it was first added with.

*Listing 20.5* (`examples/book/ch20-libraries/listing-20-05.bas`)

<!-- run -->
```basic
Option Explicit
Dim colours As Dictionary
Set colours = CreateObject("Dictionary")
colours.CompareMode = 1
colours("Red") = RGB(255, 0, 0)
colours("Green") = RGB(0, 255, 0)
Print Hex(colours("RED")), colours.Exists("green"), colours.Keys()(0)
```

```output
FF            True          Red
```

`CompareMode = 1` treats only the letters A to Z as equal in either case. Accented letters
(`Ä` and `ä`) stay two different keys; convert such keys with `LCase` yourself if you need them
to match.

### Objects and nested Dictionaries

A value can be another Dictionary, so you can build records and trees. Use `Set` to store an
object, and chain the lookups to read inside it:

*Listing 20.6* (`examples/book/ch20-libraries/listing-20-06.bas`)

<!-- run -->
```basic
Option Explicit
Dim user As Dictionary, address As Dictionary, seen As Dictionary
Dim a As New Collection, b As New Collection

Set user = CreateObject("Dictionary")
user("name") = "Ann"
Set address = CreateObject("Dictionary")
address("city") = "Amsterdam"
Set user("address") = address
user("address")("zip") = "1012"           ' changes the same Dictionary as address
user("langs") = Array("BASIC", "C")       ' arrays are stored as a copy

Print user("name"); " lives in "; address("city"); " "; user("address")("zip")
Print user("langs")(1), TypeName(user("address"))

' objects as keys: by identity
Set seen = CreateObject("Dictionary")
seen(a) = "first"
seen(b) = "second"
Print seen(a), seen(b), seen.Count
```

```output
Ann lives in Amsterdam 1012
C             Dictionary
first         second         2 
```

Arrays are values, objects are references. You can still change one element of an array held
in a Dictionary in place: `user("langs")(1) = "Pascal"` updates the stored array (so do deeper chains, such
as `d("rows")(1)(0) = 30` for an array of arrays).

### Errors

| Error | When |
|---|---|
| 5 | `Remove` or `Key(old) = new` with a key that isn't there; a `Null` or array key; changing `CompareMode` while there are entries |
| 380 | `CompareMode` set to something other than 0 or 1 |
| 383 | assigning to `Count` |
| 450 | a member called with too few arguments |
| 457 | `Add` with a key that is already there, or renaming to one |

*Listing 20.7* (`examples/book/ch20-libraries/listing-20-07.bas`)

<!-- run -->
```basic
Option Explicit
Dim d As Dictionary
Set d = CreateObject("Dictionary")
d("plum") = 1
On Error Resume Next
d.Add "plum", 2
Print Err.Number; Err.Description
Err.Clear
d.Remove "kiwi"
Print Err.Number; Err.Description
Err.Clear
d.CompareMode = 1
Print Err.Number; Err.Description
```

```output
 457 the key is already in the Dictionary
 5 the key isn't in the Dictionary
 5 CompareMode can only be changed while the Dictionary is empty
```

### Gotchas

- **A module may be called `dictionary.bas`**: `Dim d As New Dictionary` still means the
  class there. Only a variable or parameter named `dictionary` would hide it.
- `d(key)` for a missing key gives `Empty`, which prints as nothing and compares equal to 0
  and to `""`. Use `Exists` when "not there" and "0" must be told apart.
- Keys from text are Strings: `d("1")` and `d(1)` are different entries.
- Keep the loop variable of `For Each k In d` a `Variant`: keys can be of any type.

The book example `examples/book/ch20-libraries/wordfreq` (in the [StringBuilder](#stringbuilder)
section) counts the words of a text with a Dictionary.

## JSON

JSON is the text format most web services answer in, and many programs keep their settings in
it. It writes data as objects (`{"name": "Ann", "age": 42}`), arrays (`[1, 2, 3]`), strings,
numbers, `true`, `false` and `null`, nested as deeply as needed. Boing BASIC has two functions
for it:

- `JsonParse(text)` reads JSON text and gives you ordinary values: a JSON object becomes a
  [Dictionary](#dictionary), an array becomes an array, and so on.
- `JsonStringify(value [, indent])` does the opposite: it writes values as JSON text.

So reading a web service is: fetch the text with `Http`, `JsonParse` it, then read the values
with the usual Dictionary and array syntax.

*Listing 20.8* (`examples/book/ch20-libraries/listing-20-08.bas`)

<!-- run -->
```basic
Option Explicit
Dim text As String, doc As Variant, k As Variant
text = "{""name"": ""Boing BASIC"", ""year"": 2026, ""tags"": [""BASIC"", ""AmigaOS 4""]," & _
       " ""author"": {""name"": ""Chris"", ""city"": null}, ""open"": true}"
doc = JsonParse(text)
Print doc("name"); " ("; doc("year"); ")"
Print "first tag: "; doc("tags")(0); ", tags:"; UBound(doc("tags")) + 1
Print "by "; doc("author")("name"); IIf(IsNull(doc("author")("city")), ", city unknown", "")
For Each k In doc
    Print k; " is a "; TypeName(doc(k))
Next
```

```output
Boing BASIC ( 2026 )
first tag: BASIC, tags: 2 
by Chris, city unknown
name is a String
year is a Long
tags is a Variant()
author is a Dictionary
open is a Boolean
```

### JsonParse(text) As Variant

| JSON | becomes | test it with |
|---|---|---|
| object `{...}` | a `Dictionary`, with the keys in the order of the text | `IsObject(v)` |
| array `[...]` | a Variant array, `0` to `n - 1`; an empty array has `UBound` -1 | `IsArray(v)` |
| string `"..."` | a String | `VarType(v) = vbString` |
| a whole number that fits a Long | a `Long` | |
| any other number (`2.5`, `1e3`, `3000000000`) | a `Double` | |
| `true`, `false` | a `Boolean` | |
| `null` | `Null` | `IsNull(v)` |

The result is a Variant: assign it with plain `=` (`doc = JsonParse(text)`), whatever the JSON
text holds. Read inside it by chaining: `doc("items")(0)("name")` is the name of the first
item of the `items` array. `For Each k In doc("author")` walks the keys of an object.

A missing key reads as `Empty` (as in any Dictionary), so `doc("price")` for a document without
a price is not an error; check with `doc.Exists("price")` when it matters. When a key appears
twice in the text, the last value wins.

Arrays in the result are values and objects are references, as everywhere in Boing BASIC.
`Set author = doc("author")` and `author("city") = "Leiden"` change the document; to change an
array, copy it out, change the copy and put it back: `tags = doc("tags")`, `tags(0) = "Basic"`,
`doc("tags") = tags`.

#### Text in JSON is UTF-8

JSON text is UTF-8, so a letter beyond plain ASCII (`é`, `ü`, or the euro sign) arrives as
two to four bytes of UTF-8, and `\u00e9` escapes are turned into UTF-8 bytes too.
`JsonParse` leaves Strings as those bytes, so that `JsonStringify` writes them back
unchanged. Before you show a String on the Amiga's screen, convert it with `Utf8Decode` (see [Text encodings](#text-encodings)):

*Listing 20.9* (`examples/book/ch20-libraries/listing-20-09.bas`)

<!-- run -->
```basic
Option Explicit
Dim word As String
word = JsonParse("""caf\u00e9""")      ' the JSON text "caf\u00e9"
Print Len(word); " bytes; as Latin-1:"; Len(Utf8Decode(word)); " characters"
```

```output
 5  bytes; as Latin-1: 4  characters
```

A UTF-8 byte order mark at the start of the text is skipped.

### JsonStringify(value [, indent]) As String

| value | written as |
|---|---|
| a `Dictionary` | an object; number and Boolean keys are written as strings (`"1"`, `"True"`) |
| a one-dimensional array, a `Collection` | an array |
| numbers | numbers, with as many digits as it takes to read them back exactly; `NaN` and infinity as `null` |
| a String | a string: `"`, `\` and control characters are escaped, other bytes are written as they are |
| `True`, `False` | `true`, `false` |
| `Null`, `Empty`, `Nothing` | `null` |
| a Date | an ISO 8601 string, `"1985-07-23T10:30:05"` |

`indent` is the number of spaces per level, 0 to 16. Without it (or with 0) everything goes on
one line, the compact form to send to a server; 2 or 4 gives the usual readable layout, for
files and for people.

*Listing 20.10* (`examples/book/ch20-libraries/listing-20-10.bas`)

<!-- run -->
```basic
Option Explicit
Dim order As Dictionary, customer As Dictionary
Set order = CreateObject("Dictionary")
order("id") = 1001
order("items") = Array("apple", "pear")
order("total") = 3.75
order("paid") = True
order("note") = Null
Set customer = CreateObject("Dictionary")
customer("name") = "Ann ""the Amiga"" Smith"
Set order("customer") = customer

Print JsonStringify(order)
Print JsonStringify(order, 2)
```

```output
{"id":1001,"items":["apple","pear"],"total":3.75,"paid":true,"note":null,"customer":{"name":"Ann \"the Amiga\" Smith"}}
{
  "id": 1001,
  "items": [
    "apple",
    "pear"
  ],
  "total": 3.75,
  "paid": true,
  "note": null,
  "customer": {
    "name": "Ann \"the Amiga\" Smith"
  }
}
```

A value doesn't have to be an object: `JsonStringify(42)` is `42`, `JsonStringify("hi")` is
`"hi"` (with the quotes).

`JsonStringify` writes String bytes as they are. Text typed on the Amiga is Latin-1: convert it
with `Utf8Encode` before it goes into a document you send to a web service, so that `é` arrives
as `é`.

### Reading and changing a document

A typical round trip: read a settings file, change a value, write it back.

*Listing 20.11* (`examples/book/ch20-libraries/listing-20-11.bas`)

<!-- run -->
```basic
Option Explicit
Dim settings As Variant, recent As Variant
settings = JsonParse("{""volume"": 48, ""recent"": [""RAM:a.txt"", ""RAM:b.txt""]}")
settings("volume") = settings("volume") + 16
recent = settings("recent")                ' a copy of the array
ReDim Preserve recent(UBound(recent) + 1)
recent(UBound(recent)) = "RAM:c.txt"
settings("recent") = recent                ' put the changed copy back
settings("saved") = #2026-11-10 08:45:00#
Print JsonStringify(settings)
```

```output
{"volume":64,"recent":["RAM:a.txt","RAM:b.txt","RAM:c.txt"],"saved":"2026-11-10T08:45:00"}
```

### Errors

| Error | When |
|---|---|
| 31201 | `JsonParse`: the text isn't valid JSON, or is nested more than 512 levels deep. The message says what was expected and where: line, column and the character found |
| 31202 | `JsonStringify`: a value that can't be JSON: an object other than a Dictionary or Collection, an array with more than one dimension, an object used as a Dictionary key, nesting deeper than 512 levels, or a Dictionary that contains itself |
| 5 | `JsonStringify` with an `indent` outside 0 to 16 |

*Listing 20.12* (`examples/book/ch20-libraries/listing-20-12.bas`)

<!-- run -->
```basic
Option Explicit
Dim v As Variant, grid(2, 2) As Long, d As Dictionary
On Error Resume Next
v = JsonParse("{""a"": 1,}")
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("{'a': 1}")                 ' JSON strings take double quotes only
Print Err.Number; Err.Description
Err.Clear
v = JsonParse("[1, 2] 3")
Print Err.Number; Err.Description
Err.Clear
Print JsonStringify(grid)
Print Err.Number; Err.Description
Err.Clear
Set d = CreateObject("Dictionary")
Set d("me") = d
Print JsonStringify(d)
Print Err.Number; Err.Description
```

```output
 31201 JSON: a key (a string) was expected at line 1, column 9 (found '}')
 31201 JSON: a key (a string) was expected at line 1, column 2 (found ''')
 31201 JSON: text after the value at line 1, column 8 (found '3')
 31202 JSON: only one-dimensional arrays can be written
 31202 JSON: nested too deeply (or a Dictionary contains itself)
```

Text from the network can be anything (an error page in HTML, half a document after a broken
connection), so put `JsonParse` of a web answer under `On Error` and tell the user what went
wrong, as the example below does.

### JSON from a web service

`Http` fetches the text, `JsonParse` reads it. Ask the server for JSON with an `Accept` header,
and check the status before you parse:

*Listing 20.13* (`examples/book/ch20-libraries/listing-20-13.bas`)

```basic
Option Explicit
Dim web As Http, user As Variant
Set web = CreateObject("Http")
web.SetHeader "Accept", "application/json"
On Error GoTo Failed
user = JsonParse(web.Get("https://jsonplaceholder.typicode.com/users/1"))
If web.Status <> 200 Then Print "The server said "; web.Status: End
Print Utf8Decode(user("name")); " lives in "; Utf8Decode(user("address")("city"))
End
Failed:
Print "Error"; Err.Number; ": "; Err.Description
```

Sending works the other way round: build a Dictionary, `JsonStringify` it, and `Post` it with
the content type `application/json`:

*Listing 20.14* (`examples/book/ch20-libraries/listing-20-14.bas`)

```basic
Option Explicit
Dim web As Http, post As Dictionary, reply As Variant
Set web = CreateObject("Http")
Set post = CreateObject("Dictionary")
post("title") = Utf8Encode("Hello from the Amiga")
post("userId") = 1
reply = JsonParse(web.Post("https://jsonplaceholder.typicode.com/posts", _
                           JsonStringify(post), "application/json"))
If web.Status = 201 Then Print "Created post"; reply("id")
```

### A JSON viewer

The book example `jsonview` fetches any JSON address and shows every value of the document as
one line, `path = value`, in a list: `address.geo.lat = "-37.3159"`, `company.name = ...`. The
**Show JSON** button pretty-prints the whole document with `JsonStringify(doc, 2)`. Its form:

```text
window name=jsonview title="JSON Viewer" width=560 height=360 resizable=1
vlayout id=root
  hlayout weight=0
    string id=url label="URL" text="https://jsonplaceholder.typicode.com/users/1" maxchars=1024
    button id=go text="_Get" weight=0
  listbrowser id=tree
  hlayout weight=0
    label id=status text="Type the URL of a JSON service and press Get"
    button id=pretty text="Show _JSON" weight=0
```

The heart of its code is `Walk`, a procedure that calls itself for every object and array it
meets, building the path as it goes down:

*Listing 20.15* (`examples/book/ch20-libraries/jsonview/jsonview.bbp`)

<!-- project: examples/book/ch20-libraries/jsonview/jsonview.bbp -->
```basic
Private Sub Fetch()
    Dim body As String
    On Error GoTo Failed
    status.Caption = "Fetching ..."
    DoEvents
    body = web.Get(url.Text)
    If web.Status <> 200 Then
        status.Caption = "HTTP " & web.Status & " " & web.StatusText
        Exit Sub
    End If
    doc = JsonParse(body)               ' error 31201 if it isn't JSON
    tree.Clear
    Walk "", doc
    status.Caption = tree.ListCount & " values from " & web.Url
    Exit Sub
Failed:
    If Err.Number = 31201 Then
        status.Caption = "The answer isn't JSON: " & Err.Description
    Else
        status.Caption = "Error " & Err.Number & ": " & Err.Description
    End If
End Sub

' every scalar of the document as one line "path = value"
Private Sub Walk(path As String, v As Variant)
    Dim k As Variant, i As Long
    If IsObject(v) Then                 ' a JSON object: a Dictionary
        For Each k In v
            Walk path & "." & k, v(k)
        Next
    ElseIf IsArray(v) Then              ' a JSON array: 0 To UBound
        For i = 0 To UBound(v)
            Walk path & "[" & i & "]", v(i)
        Next
    ElseIf IsNull(v) Then
        tree.AddItem Mid(path, 2) & " = null"
    ElseIf VarType(v) = vbString Then   ' JSON text is UTF-8: decode it for the Amiga's screen
        tree.AddItem Mid(path, 2) & " = """ & Utf8Decode(v) & """"
    Else                                ' Long, Double or Boolean
        tree.AddItem Mid(path, 2) & " = " & v
    End If
End Sub
```

Run it from the Shell with an address to fetch straight away:
`boing run jsonview.bbp https://api.github.com/repos/geekychris/boing-basic`.

### Limits

- Strings keep their UTF-8 bytes: decode them for display with `Utf8Decode`.
- Numbers are a Long or a Double: whole numbers beyond about 15 digits (some IDs in web
  services) lose their last digits. Ask the service for such IDs as strings if it offers that.
- `-0` is read as a Double and written back as `-0`.
- The whole text is read into memory at once; a document of a few megabytes is fine, but
  needs that much memory two or three times over while it is parsed.

## Text encodings

These functions move text and binary data between the Amiga and the rest of the world: from
the Amiga's character set to the one the web uses and back (UTF-8), and into the forms that
let any bytes travel through text (Base64, URL encoding, hex).

| Function | What it does |
|---|---|
| `Utf8Encode(s)` | Latin-1 text (the Amiga's character set) -> UTF-8 bytes |
| `Utf8Decode(s [, replacement])` | UTF-8 bytes -> Latin-1 text. A character Latin-1 doesn't have, and a byte that isn't valid UTF-8, becomes `replacement`: `"?"` if you leave it out, `""` drops it |
| `Base64Encode(s [, lineLength])` | bytes -> Base64 text. With `lineLength` (76 for e-mail) the text is broken into lines of that length with CR LF; 0, the default, gives one line |
| `Base64Decode(s)` | Base64 text -> bytes. Spaces and line breaks are skipped, the `=` padding may be left out, and the URL-safe alphabet (`-` and `_` for `+` and `/`) is read too |
| `UrlEncode(s)` | percent-encoding for URLs and form data: letters, digits and `- _ . ~` stay as they are, every other byte becomes `%XX` (a space is `%20`) |
| `UrlDecode(s)` | `%XX` -> that byte, `+` -> a space |
| `HexEncode(s)` | bytes -> two hex digits each, in capitals: `"Boing!"` -> `"426F696E6721"` |
| `HexDecode(s)` | hex digits -> bytes; spaces, line breaks and `:` between the digits are skipped, either case is read |

A Boing BASIC String holds bytes, any bytes, not only letters. So all of these work on binary
data as well as text: an image read from a file, a hash from `Sha256(s, True)`, the body of a
download.

### Why UTF-8 matters on the Amiga

The Amiga uses Latin-1 (ISO 8859-1): one byte per character, and the 256 characters include the
letters of the Western European languages (`é`, `ü`, `ß`, `ø`...). Most of the rest of the
world now uses UTF-8, which can write every character there is: plain ASCII letters are one
byte, as in Latin-1, but every other character takes two to four bytes. Web pages, JSON from web
services, and text files from other computers are nearly always UTF-8.

So the two agree on `A` to `Z`, digits and punctuation, and disagree on everything else. Show a
UTF-8 `é` on the Amiga without converting it and you see two characters, `Ã©`; send an Amiga
`é` to a web service as it is and the service sees a byte that isn't valid UTF-8, and either
refuses the text or shows a replacement sign.

The rule is simple: decode what comes in, encode what goes out.

*Listing 20.16* (`examples/book/ch20-libraries/listing-20-16.bas`)

```basic
Option Explicit
Dim web As Http, page As String, reply As String, name As String
Set web = CreateObject("Http")
page = web.Get("https://example.com/")
Print Utf8Decode(page)                           ' in: UTF-8 -> Latin-1, for the screen
name = "Zoë"
reply = web.Post("https://example.com/hello", Utf8Encode(name), "text/plain; charset=utf-8")
```

Characters that Latin-1 doesn't have (the euro sign, Greek, Cyrillic, Chinese, emoji) can't be
shown on the Amiga's Latin-1 screens at all: `Utf8Decode` puts the replacement in their place.

*Listing 20.17* (`examples/book/ch20-libraries/listing-20-17.bas`)

<!-- run -->
```basic
Option Explicit
Dim amiga As String, utf8 As String, euro As String
amiga = "Caf" & Chr(233)                       ' "Café" in Latin-1: 4 bytes
utf8 = Utf8Encode(amiga)
Print Len(amiga); Len(utf8); " "; HexEncode(utf8)
Print Utf8Decode(utf8) = amiga                 ' and back
euro = HexDecode("E282AC") & "5"               ' "5 euros" in UTF-8: the euro sign is 3 bytes
Print Utf8Decode(euro); " "; Utf8Decode(euro, "EUR "); " "; Utf8Decode(euro, "")
Print Utf8Decode(HexDecode("41FF42"))          ' FF is never valid UTF-8
```

```output
 4  5  436166C3A9
True
?5 EUR 5 5
A?B
```

Plain ASCII text is the same in both, so `Utf8Encode` and `Utf8Decode` leave it alone: it is
safe to convert text that might already be plain.

Don't decode twice, and don't encode twice: `Utf8Encode(Utf8Encode(s))` turns `é` into four
bytes that decode to `Ã©`. Convert at the edge of your program, where text comes in or goes out,
and keep Latin-1 inside.

### Base64

Base64 writes any bytes with 64 safe characters (`A-Z`, `a-z`, `0-9`, `+`, `/`, and `=` at the
end), four characters for every three bytes. It is how e-mail carries attachments, how a
password goes into an HTTP `Authorization` header, and how binary data fits into JSON or XML.

*Listing 20.18* (`examples/book/ch20-libraries/listing-20-18.bas`)

<!-- run -->
```basic
Option Explicit
Dim b As String
b = Base64Encode("Boing!")
Print b, Base64Decode(b)
Print Base64Encode("Boi"), Base64Encode("Bo"), Base64Encode("B")
Print Base64Decode("Qm9p bmch"), Base64Decode("Qm8")       ' spaces skipped, "=" optional
Print HexEncode(Base64Decode("-_8")), HexEncode(Base64Decode("+/8="))   ' both alphabets
Print Len(Base64Encode(String(100, "x"), 76))              ' 76 + CR LF + 60
```

```output
Qm9pbmch      Boing!
Qm9p          Qm8=          Qg==
Boing!        Bo
FBFF          FBFF
 138 
```

The everyday use, HTTP Basic authentication:

*Listing 20.19* (`examples/book/ch20-libraries/listing-20-19.bas`)

```basic
Option Explicit
Dim web As Http, user As String, password As String, page As String
Set web = CreateObject("Http")
user = "ann": password = "secret"
web.SetHeader "Authorization", "Basic " & Base64Encode(user & ":" & password)
page = web.Get("https://example.com/private/")
```

Base64 is not encryption: anyone can decode it. Send passwords only over `https://`.

### URL encoding

A URL may contain only some characters; `&`, `=`, `?`, `/`, `#`, spaces and every non-ASCII byte
have to be written as `%` and two hex digits when they are part of a value. `UrlEncode` does that
for one value (a search word, a file name); apply it to each value, not to the whole URL, or the
`?`, `&` and `=` between the values are encoded too.

Encode Amiga text to UTF-8 first: web servers expect `%C3%A9` for `é`, not `%E9`.

*Listing 20.20* (`examples/book/ch20-libraries/listing-20-20.bas`)

<!-- run -->
```basic
Option Explicit
Dim q As String, url As String
q = "Boing BASIC & AmigaOS 4"
url = "https://example.com/search?q=" & UrlEncode(q) & "&page=2"
Print url
Print UrlEncode(Utf8Encode("Caf" & Chr(233)))
Print UrlDecode("Boing+BASIC%21"), UrlDecode("a%2Fb")
```

```output
https://example.com/search?q=Boing%20BASIC%20%26%20AmigaOS%204&page=2
Caf%C3%A9
Boing BASIC!  a/b
```

`UrlDecode` reads a `+` as a space, as HTML forms send them. That is how to take a form's POST
body (`name=Boing+BASIC&year=1985`) apart into a Dictionary:

*Listing 20.21* (`examples/book/ch20-libraries/listing-20-21.bas`)

<!-- run -->
```basic
Option Explicit
Dim body As String, fields As Dictionary, pair As Variant, kv As Variant, k As Variant
body = "name=Boing+BASIC&year=1985&note=100%25+BASIC"
Set fields = CreateObject("Dictionary")
For Each pair In Split(body, "&")
    kv = Split(pair, "=")
    fields(UrlDecode(kv(0))) = Utf8Decode(UrlDecode(kv(1)))
Next
For Each k In fields
    Print k; " = "; fields(k)
Next
```

```output
name = Boing BASIC
year = 1985
note = 100% BASIC
```

### Hex

`HexEncode` writes each byte as two hex digits, which makes binary data readable: the start of a
file, a checksum, a key. `HexDecode` reads them back and skips spaces, line breaks and colons, so
it accepts `42 6F 69` and `42:6F:69` as well as `426F69`.

*Listing 20.22* (`examples/book/ch20-libraries/listing-20-22.bas`)

<!-- run -->
```basic
Option Explicit
Print HexEncode("Boing!")
Print HexDecode("42 6f:69 6E 67 21")
Print HexEncode(Chr(0) & Chr(255) & vbCrLf)
```

```output
426F696E6721
Boing!
00FF0D0A
```

`HexEncode` writes capitals. The hash functions in the next section write their hex digits in
small letters, as is usual for hashes; compare them with `LCase` if you mix the two.

### Errors

The decoders raise error **31301** for input they can't read, saying what was wrong and at
which character (counting from 1):

*Listing 20.23* (`examples/book/ch20-libraries/listing-20-23.bas`)

<!-- run -->
```basic
Option Explicit
Dim s As String
On Error Resume Next
s = Base64Decode("ab$d")
Print Err.Number; Err.Description
Err.Clear
s = Base64Decode("ab=c")
Print Err.Number; Err.Description
Err.Clear
s = UrlDecode("100%")
Print Err.Number; Err.Description
Err.Clear
s = HexDecode("ABC")
Print Err.Number; Err.Description
Err.Clear
s = HexDecode("AG")
Print Err.Number; Err.Description
```

```output
 31301 Base64: a character that isn't Base64 at character 3
 31301 Base64: data after the '=' padding at character 4
 31301 URL: '%' isn't followed by two hex digits at character 4
 31301 hex: an odd number of digits at character 3
 31301 hex: a character that isn't a hex digit at character 2
```

`Utf8Decode` never raises an error: bytes that aren't valid UTF-8 become the replacement.
`UrlDecode` does raise one for a `%` that isn't followed by two hex digits, since such a URL
wasn't encoded properly. A negative `lineLength` for `Base64Encode` is error 5.

## Checksums and hashes

A checksum or hash turns any amount of data into a short value of fixed size. The same data
always gives the same value, and even a one-byte change gives a completely different one. That
makes hashes useful for checking that a download or a file arrived undamaged, for recognising
data you have seen before, and (with a key, as an HMAC) for proving that a message came from
someone who knows a secret.

| Function | Result |
|---|---|
| `Crc32(s)` | the CRC-32 checksum of `s` (the one used by Zip, PNG and gzip), as a Long |
| `Md5(s [, raw])` | the MD5 hash: 32 hex digits |
| `Sha1(s [, raw])` | the SHA-1 hash: 40 hex digits |
| `Sha256(s [, raw])` | the SHA-256 hash: 64 hex digits |
| `HmacSha1(key, s [, raw])` | the HMAC of `s` with `key`, using SHA-1: 40 hex digits |
| `HmacSha256(key, s [, raw])` | the HMAC of `s` with `key`, using SHA-256: 64 hex digits |

The hex digits are small letters (`ba7816bf...`), the way hashes are usually written. With
`raw` = `True` you get the hash as its bytes instead: 16 bytes for MD5, 20 for SHA-1, 32 for
SHA-256. The raw form is what you pass to `Base64Encode`, or into another hash.

A String holds bytes, so you can hash any data: text, the body of a download, a whole file
read into a String. All of these functions are written in portable C inside Boing BASIC: they
work the same on AmigaOS 4 and on other systems, and they don't need AmiSSL.

### Known answers

Every one of these algorithms has published test values. The program below prints the hashes of
the standard test messages; the values are the ones in the standards (RFC 1321 for MD5,
FIPS 180 for SHA-1 and SHA-256, RFC 2202 and RFC 4231 for the HMACs):

*Listing 20.24* (`examples/book/ch20-libraries/listing-20-24.bas`)

<!-- run -->
```basic
Option Explicit
Print Hex(Crc32("123456789"))
Print Md5("")
Print Md5("abc")
Print Sha1("abc")
Print Sha256("abc")
Print HmacSha1("Jefe", "what do ya want for nothing?")
Print HmacSha256("Jefe", "what do ya want for nothing?")
```

```output
CBF43926
d41d8cd98f00b204e9800998ecf8427e
900150983cd24fb0d6963f7d28e17f72
a9993e364706816aba3e25717850c26c9cd0d89d
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
effcdf6ae5eb2fa2d27416d5f184df9c259a7c79
5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
```

`CBF43926` is the check value of CRC-32: if a CRC routine gives that for `"123456789"`, it
computes the same checksum as everyone else.

### Raw digests

*Listing 20.25* (`examples/book/ch20-libraries/listing-20-25.bas`)

<!-- run -->
```basic
Option Explicit
Dim digest As String
digest = Sha256("abc", True)
Print Len(digest); " bytes"
Print HexEncode(digest)                      ' the same digits, in capitals
Print Base64Encode(HmacSha256("key", "The quick brown fox jumps over the lazy dog", True))
Print Sha256(Sha256("abc", True))            ' a hash of a hash: SHA-256 twice
```

```output
 32  bytes
BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD
97yD9DBThCSxMpjmqm+xQ+9NWaFJRhdZl0edvC0aPNg=
4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358
```

Services that sign their requests usually want the HMAC in Base64: that is
`Base64Encode(HmacSha256(secret, message, True))`, not the Base64 of the hex digits.

### Checking a file or a download

Read the whole file into a String in Binary mode and hash that. The program writes a small file
first so that it has something to check:

*Listing 20.26* (`examples/book/ch20-libraries/listing-20-26.bas`)

<!-- run -->
```basic
Option Explicit
Dim f As Integer, data As String

f = FreeFile
Open "test.dat" For Output As #f
Print #f, "Boing BASIC";
Close #f

f = FreeFile
Open "test.dat" For Binary Access Read As #f
data = Space(LOF(f))
Get #f, , data
Close #f
Kill "test.dat"

Print Len(data); " bytes, CRC-32 "; Hex(Crc32(data))
Print "SHA-256 "; Sha256(data)
```

```output
 11  bytes, CRC-32 185CFCEA
SHA-256 34ef03e23794a03c20d8d124f78b786f3d03eff9441859af09e55248453a7460
```

A download you check against the hash its web site publishes:

*Listing 20.27* (`examples/book/ch20-libraries/listing-20-27.bas`)

```basic
Option Explicit
Const EXPECTED = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
Dim web As Http, data As String
Set web = CreateObject("Http")
data = web.Get("https://example.com/files/game.lha")
If Sha256(data) <> EXPECTED Then
    MsgBox "The download is damaged: please try again", vbExclamation
End If
```

Hex digits from a web page may be in capitals; compare with `LCase(published) = Sha256(data)`.

### Signing a request

An HMAC mixes a secret key into the hash. Someone who has the message but not the key can't make
the right HMAC, so a server that shares the key with you can tell that a request really came from
you and wasn't changed on the way:

*Listing 20.28* (`examples/book/ch20-libraries/listing-20-28.bas`)

```basic
Option Explicit
Dim web As Http, secret As String, body As String, reply As String
Set web = CreateObject("Http")
secret = "my-api-secret"
body = "{""order"": 1001}"
web.SetHeader "X-Signature", Base64Encode(HmacSha256(secret, body, True))
reply = web.Post("https://api.example.com/orders", body, "application/json")
```

The exact recipe (which hash, hex or Base64, what goes into the message) is set by the service:
follow its documentation.

### Which one to use

- **`Crc32`** to notice accidental damage: a broken download, a bad sector, a changed file. It
  is very fast, but anyone can make other data with the same CRC on purpose, so it proves nothing
  against an attacker.
- **`Sha256`** to identify or check data when it matters: downloads, caches, "has this file
  changed?".
- **`HmacSha256`** to prove that a message came from someone who knows the key.
- **`Md5`**, **`Sha1`** and **`HmacSha1`** are there for file formats and services that still
  ask for them. They are broken for security purposes: don't choose them for anything new.

None of these is a way to store passwords: a hash of a password can be guessed back quickly by
trying common passwords.

### Speed

Hashing one million bytes takes a few milliseconds on a modern computer and a fraction of a
second on an emulated AmigaOS 4 machine. `Crc32` is the fastest, then MD5, SHA-1 and SHA-256.

### Gotchas

- `Crc32` returns a **Long**, and a Long is signed: half of all checksums are negative numbers
  (`Crc32("123456789")` is -873187034). Compare checksums as Longs, or as hex text.
- `Hex` leaves out leading zeros: `Hex(Crc32(""))` is `"0"`. When you need the usual eight
  digits, pad them: `Right("0000000" & Hex(Crc32(s)), 8)`.
- Text typed on the Amiga is Latin-1. If a service computes its hash over UTF-8 text, hash
  `Utf8Encode(s)`, or the two hashes differ as soon as there is an accented letter.
- Line ends count: `"abc" & vbLf` and `"abc" & vbCrLf` have different hashes. `Print #` adds a
  line end unless the line ends with `;`.

## Dates and times in UTC

Boing BASIC's `Date` values (`Now`, `Date`, `DateSerial`, `#2026-11-10 08:45#`) are in local
time: the time on the Amiga's clock. That is right for showing a time to the user, but other
computers need a time that means the same everywhere. Web services, JSON documents, log files
and file formats from other systems use UTC (Coordinated Universal Time, the time at
Greenwich without summer time), written as ISO 8601 text such as `2026-11-10T08:45:00Z`, or as
Unix time, a number of seconds.

These functions convert between the three:

| Function | Returns | What it does |
|---|---|---|
| `NowUtc()` | Date | the current date and time in UTC |
| `UtcOffset()` | Long | how many minutes local time is ahead of UTC: 60 in Central Europe in winter, 120 in summer, -300 in New York in winter, 0 in London in winter |
| `LocalToUtc(d)` | Date | a local Date as UTC, using the current offset |
| `UtcToLocal(d)` | Date | a UTC Date as local time, using the current offset |
| `UnixTime(d)` | Double | the seconds from 1970-01-01 00:00 UTC to the UTC Date `d`; milliseconds are kept as a fraction |
| `FromUnixTime(seconds)` | Date | the UTC Date of a Unix time |
| `FormatIso8601(d [, offset])` | String | `d` as ISO 8601 text, `2026-11-10T08:45:00`; see below |
| `ParseIso8601(s)` | Date | reads ISO 8601 text; see below |

A Date doesn't know whether it holds local time or UTC: that is up to your program. A good
habit is to name variables so you can tell (`createdUtc`), keep UTC inside the program and in
files, and turn it into local time only when you show it.

*Listing 20.29* (`examples/book/ch20-libraries/listing-20-29.bas`)

<!-- run -->
```basic
Option Explicit
Dim t As Date
t = FromUnixTime(1700000000)
Print FormatIso8601(t, 0)
Print UnixTime(#1970-01-01#); UnixTime(#2000-01-01#)
Print FormatIso8601(FromUnixTime(1700000000.25), 0)    ' milliseconds are kept
Print Format(t, "dd.mm.yyyy hh:nn:ss")
```

```output
2023-11-14T22:13:20Z
 0  946684800 
2023-11-14T22:13:20.250Z
14.11.2023 22:13:20
```

### Unix time

Unix time counts the seconds since the start of 1970 in UTC, without leap seconds. Web
services, databases and file formats from Unix systems use it a lot. `UnixTime` gives a Double,
so dates after 2038 (when the seconds no longer fit a Long) and before 1970 (negative values)
work, and a fraction holds the milliseconds. Some services count in milliseconds instead:
divide by 1000 before `FromUnixTime`.

*Listing 20.30* (`examples/book/ch20-libraries/listing-20-30.bas`)

<!-- run -->
```basic
Option Explicit
Print FormatIso8601(FromUnixTime(-86400), 0)
Print FormatIso8601(FromUnixTime(2147483647), 0)          ' the largest Long
Print UnixTime(ParseIso8601("2038-01-19T03:14:08Z"))      ' one second later
Print FormatIso8601(FromUnixTime(1731228300123# / 1000), 0)  ' milliseconds from a service
```

```output
1969-12-31T00:00:00Z
2038-01-19T03:14:07Z
 2147483648 
2024-11-10T08:45:00.123Z
```

### FormatIso8601(d [, offset])

Writes a Date as ISO 8601 text, `yyyy-mm-ddThh:nn:ss`. Milliseconds are added (`.250`) only when
the Date has any. The optional `offset` says which time zone the Date is in:

| `offset` | writes | means |
|---|---|---|
| left out | `2026-11-10T08:45:00` | no zone: "local time somewhere" |
| `0` | `2026-11-10T08:45:00Z` | the Date is UTC |
| other numbers (minutes ahead of UTC) | `2026-11-10T08:45:00+01:00`, `-05:30` | the Date is local time in that zone |

*Listing 20.31* (`examples/book/ch20-libraries/listing-20-31.bas`)

<!-- run -->
```basic
Option Explicit
Dim d As Date
d = #2026-11-10 08:45:00#
Print FormatIso8601(d)
Print FormatIso8601(d, 0)
Print FormatIso8601(d, 60)
Print FormatIso8601(d, -330)
```

```output
2026-11-10T08:45:00
2026-11-10T08:45:00Z
2026-11-10T08:45:00+01:00
2026-11-10T08:45:00-05:30
```

`offset` only writes the zone: it doesn't convert the time. To write the current time for a web
service, take `NowUtc()` and write it with `Z`: `FormatIso8601(NowUtc(), 0)`. Or write the local
time with its zone: `FormatIso8601(Now, UtcOffset())`. Both name the same moment.

`JsonStringify` writes Dates with `FormatIso8601(d)`, without a zone; convert to UTC and use
`FormatIso8601(d, 0)` yourself when the service wants UTC.

### ParseIso8601(s)

Reads the ISO 8601 forms you meet in practice:

| text | |
|---|---|
| `2026-11-10` | a date; the time is midnight |
| `2026-11-10T08:45` | without seconds |
| `2026-11-10T08:45:00`, `2026-11-10 08:45:00` | `T` or a space between date and time |
| `2026-11-10T08:45:00.250` | with a fraction of a second (`.` or `,`) |
| `20261110T084500` | the compact form, without `-` and `:` |
| `...Z`, `...+01:00`, `...-0530`, `...+01` | with a time zone |

With a time zone (`Z` or an offset) the result is converted to **UTC**. Without one the Date is
returned as written. Spaces before and after are skipped.

*Listing 20.32* (`examples/book/ch20-libraries/listing-20-32.bas`)

<!-- run -->
```basic
Option Explicit
Print FormatIso8601(ParseIso8601("2026-11-10"))
Print FormatIso8601(ParseIso8601("2026-11-10T08:45"))
Print FormatIso8601(ParseIso8601("20261110T084500Z"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10 08:45:00+01:00"), 0)
Print FormatIso8601(ParseIso8601("2026-11-10T00:30:00+01:00"), 0)   ' the day before in UTC
Print FormatIso8601(ParseIso8601("2026-11-10T08:45:00,5"))
```

```output
2026-11-10T00:00:00
2026-11-10T08:45:00
2026-11-10T08:45:00Z
2026-11-10T07:45:00Z
2026-11-09T23:30:00Z
2026-11-10T08:45:00.500
```

A time from a web service, shown to the user in local time:

*Listing 20.33* (`examples/book/ch20-libraries/listing-20-33.bas`)

```basic
Option Explicit
Dim item As Variant, created As Date
item = JsonParse("{""created_at"": ""2026-11-10T08:45:00Z""}")
created = UtcToLocal(ParseIso8601(item("created_at")))
Print "Created "; Format(created, "dd.mm.yyyy hh:nn")
```

### Local time and UTC

`NowUtc()` is `Now` minus `UtcOffset()` minutes, and `LocalToUtc` and `UtcToLocal` add or
subtract the same offset. This program is true wherever it runs:

*Listing 20.34* (`examples/book/ch20-libraries/listing-20-34.bas`)

<!-- run -->
```basic
Option Explicit
Dim d As Date
Print Abs((Now - NowUtc()) * 1440 - UtcOffset()) < 0.01
d = #2026-07-01 12:00:00#
Print LocalToUtc(UtcToLocal(d)) = d
Print TypeName(UtcOffset()), TypeName(UnixTime(Now))
```

```output
True
True
Long          Double
```

#### Where the offset comes from

- **On AmigaOS** the clock runs on local time, and the offset is the time zone chosen in the
  Locale preferences (locale.library). If the clock or the time zone in Locale is wrong, so is
  every UTC time your program computes.
- **On macOS and Linux** it is the system's time zone.
- **`BOING_UTC_OFFSET`**: when this environment variable is set, its value (minutes ahead of
  UTC) is used instead, on any system. It is meant for machines whose clock and time zone
  setting don't agree, such as an emulator whose clock runs on UTC while Locale names another
  zone. In the AmigaOS Shell:

```sh
setenv BOING_UTC_OFFSET 0
```

  Put the line in `S:User-Startup` to keep it after a reboot; `unsetenv BOING_UTC_OFFSET`
  removes it again.

### Errors

`ParseIso8601` raises error **31401** for text it can't read, saying what was wrong:

*Listing 20.35* (`examples/book/ch20-libraries/listing-20-35.bas`)

<!-- run -->
```basic
Option Explicit
Dim d As Date
On Error Resume Next
d = ParseIso8601("10.11.2026")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-13-01")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-11-10T25:00")
Print Err.Number; Err.Description
Err.Clear
d = ParseIso8601("2026-11-10 08:45 CET")
Print Err.Number; Err.Description
```

```output
 31401 ISO 8601: the year is missing in "10.11.2026"
 31401 ISO 8601: the month or day is out of range in "2026-13-01"
 31401 ISO 8601: the time is out of range in "2026-11-10T25:00"
 31401 ISO 8601: unexpected text at the end in "2026-11-10 08:45 CET"
```

### Gotchas

- `LocalToUtc` and `UtcToLocal` use the offset **now**. A date in summer converted in winter is
  an hour off in countries with summer time: for times far from today, keep them in UTC and
  convert only the ones near now, or let the service send the offset (`+02:00`) with the time.
- `ParseIso8601` checks that the day is 1 to 31 but not that the month has that many days:
  `2026-02-31` is read as 3 March.
- Hours may go up to 24 and seconds up to 60 (`24:00` is midnight at the end of the day, `:60`
  is a leap second); both roll over into the next minute or day.
- Text without a zone is returned as written: you have to know whether the service meant UTC
  or local time. Most APIs send UTC with a `Z`.

## StringBuilder

`s = s & piece` is the natural way to build a text, and for a few dozen pieces it is all you
need. But each `&` makes a new String and copies the whole of `s` into it, so the work grows with
the square of the length: building a report, a web page or a file of 100 KB from thousands of
small pieces gets slower and slower, and on an Amiga it can take seconds.

A `StringBuilder` keeps the text in a buffer that grows in large steps. Adding a piece copies
only that piece, so a thousand appends cost about a thousand times one append.

*Listing 20.36* (`examples/book/ch20-libraries/listing-20-36.bas`)

<!-- run -->
```basic
Option Explicit
Dim sb As StringBuilder, i As Long
Set sb = CreateObject("StringBuilder")
For i = 1 To 5
    sb.Append "line "
    sb.AppendLine CStr(i)
Next
Print sb.ToString;
Print sb.Length; "characters"
```

```output
line 1
line 2
line 3
line 4
line 5
 35 characters
```

### When to use it

Use a StringBuilder when you build one text from many pieces in a loop: hundreds of lines for a
text editor or a file, an HTML page, a CSV export, a long log. For a handful of `&` in one
statement, plain Strings are simpler and just as fast.

How much it matters, appending `"Boing"` again and again:

| | `s = s & x` | StringBuilder |
|---|---|---|
| 20,000 appends, interpreter, AmigaOS 4 (QEMU) | 2.30 s | 0.02 s |
| 200,000 appends, interpreter, a modern Mac | 1.5 s | 0.005 s |
| 200,000 appends, native build, a modern Mac | 1.7 s | 0.002 s |

Compiling doesn't help `s = s & x`: the time goes into copying memory, not into the
interpreter. Measure it yourself with this program (it uses 20,000 appends; raise `N` on a fast
machine):

*Listing 20.37* (`examples/book/ch20-libraries/listing-20-37.bas`)

```basic
Option Explicit
Const N = 20000
Dim s As String, sb As StringBuilder, i As Long, t As Single
t = Timer
For i = 1 To N
    s = s & "Boing"
Next
Print "s = s & x:     "; Format(Timer - t, "0.000"); " s"
Set sb = CreateObject("StringBuilder")
t = Timer
For i = 1 To N
    sb.Append "Boing"
Next
Print "StringBuilder: "; Format(Timer - t, "0.000"); " s"
```

### Members

| Member | Kind | What it does |
|---|---|---|
| `Append x [, y ...]` | method | adds the text of each argument; numbers, Booleans and Dates are written as `CStr` writes them. Returns the StringBuilder, so calls can be chained: `sb.Append("a").Append("b")` |
| `AppendLine [x]` | method | adds `x` (if given) and a line feed (`vbLf`); returns the StringBuilder |
| `Insert pos, x` | method | inserts the text of `x` before position `pos`: 1 is the start, `Length + 1` the end |
| `Remove start, count` | method | removes `count` characters from position `start` |
| `Replace(find, with)` | method | replaces every `find` with `with` (case-sensitive) and returns how many it replaced |
| `Clear` | method | empties it; the buffer is kept for the next text |
| `ToString` | property | the text as a String. It is the default member: `Print sb` and `page.Text = sb` work too |
| `Length` | property | the number of characters. Setting it cuts the text short, or pads it with spaces |
| `Capacity` | property | the size of the buffer. Setting it reserves at least that much room in advance, when you know roughly how long the text will be |
| `Char(pos)` | property | the character at `pos` (1 is the first); `sb.Char(pos) = "x"` changes it |

Positions count from 1, as in `Mid`. Like a String, a StringBuilder holds bytes, so binary data
(`Chr(0)` included) is fine.

*Listing 20.38* (`examples/book/ch20-libraries/listing-20-38.bas`)

<!-- run -->
```basic
Option Explicit
Dim sb As StringBuilder, n As Long
Set sb = CreateObject("StringBuilder")
sb.Append "Boing", " ", 2026, " ", True
Print sb
sb.Insert 1, ">> "
Print sb
sb.Remove 1, 3
n = sb.Replace(" ", "_")
Print sb; " ("; n; "replaced)"
sb.Char(1) = "b"
Print sb.Char(1), sb.Length
sb.Length = 5
Print "[" & sb & "]"
sb.Length = 8
Print "[" & sb & "]"
sb.Clear
sb.Append("a").Append("b").AppendLine("c")
Print HexEncode(sb.ToString)
```

```output
Boing 2026 True
>> Boing 2026 True
Boing_2026_True ( 2 replaced)
b              15 
[boing]
[boing   ]
6162630A
```

### Errors

| Error | When |
|---|---|
| 5 | `Insert`, `Remove` or `Char` with a position outside the text; `Replace` with an empty `find`; `sb.Char(pos) = ""` |
| 380 | `Length` set to a negative number |
| 383 | assigning to `ToString` |
| 7 | out of memory |

*Listing 20.39* (`examples/book/ch20-libraries/listing-20-39.bas`)

<!-- run -->
```basic
Option Explicit
Dim sb As StringBuilder, n As Long
Set sb = CreateObject("StringBuilder")
sb.Append "Amiga"
On Error Resume Next
sb.Insert 0, "x"
Print Err.Number; Err.Description
Err.Clear
sb.Remove 3, 10
Print Err.Number; Err.Description
Err.Clear
n = sb.Replace("", "x")
Print Err.Number; Err.Description
```

```output
 5 the position is outside the text
 5 the range is outside the text
 5 the text to replace is empty
```

### Example: a word count report

The book example `wordfreq` puts the last three sections together. It counts the words of a
text with a [Dictionary](#dictionary), builds the report with a StringBuilder, and writes the
counts as [JSON](#json). The project has two modules: `WordStats.bas` does the counting, and
`main.bas` makes the report:

```ini
# wordfreq.bbp
Name=WordFreq
Startup=Sub Main
Module=main.bas
Module=WordStats.bas
```

`WordStats.bas` holds the counting. `TopWords` finds the most common words by taking the
largest count out of a copy of the Dictionary, again and again; since a Dictionary keeps its
order, words with the same count come out in the order they first appeared:

*Listing 20.40* (`examples/book/ch20-libraries/wordfreq/wordfreq.bbp`)

<!-- project: examples/book/ch20-libraries/wordfreq/wordfreq.bbp -->
```basic
' the words of text (letters, digits and ') in lower case, with how often each comes
Public Function CountWords(text As String) As Dictionary
    Dim counts As Dictionary, i As Long, ch As String, w As String
    Set counts = CreateObject("Dictionary")
    For i = 1 To Len(text) + 1
        ch = Mid(text, i, 1)
        If ch Like "[A-Za-z0-9']" Then
            w = w & LCase(ch)
        ElseIf w <> "" Then
            counts(w) = counts(w) + 1       ' a missing key reads as Empty: Empty + 1 = 1
            w = ""
        End If
    Next
    Set CountWords = counts
End Function

' the n most common words, most common first; words with the same count keep their order
Public Function TopWords(counts As Dictionary, n As Long) As Variant
    Dim rest As Dictionary, k As Variant, best As Variant, i As Long, result() As Variant
    Set rest = CreateObject("Dictionary")
    For Each k In counts
        rest(k) = counts(k)
    Next
    If n > rest.Count Then n = rest.Count
    If n = 0 Then TopWords = Array(): Exit Function
    ReDim result(n - 1)
    For i = 0 To n - 1
        best = Empty
        For Each k In rest
            If IsEmpty(best) Then
                best = k
            ElseIf rest(k) > rest(best) Then
                best = k
            End If
        Next
        result(i) = best
        rest.Remove best
    Next
    TopWords = result
End Function
```

`main.bas` builds the report with a chain of `Append` calls, and the JSON document as a
Dictionary that holds an array of Dictionaries (the top five) and the Dictionary of all the
counts:

*Listing 20.41* (`examples/book/ch20-libraries/wordfreq/wordfreq.bbp`)

<!-- project: examples/book/ch20-libraries/wordfreq/wordfreq.bbp -->
```basic
    Set counts = CountWords(text)
    top = TopWords(counts, 5)

    ' the report: many small pieces, so a StringBuilder
    Set report = CreateObject("StringBuilder")
    report.Append("Words: ").Append(TotalWords(counts)).Append(", different: ").AppendLine counts.Count
    report.AppendLine "Most common:"
    For i = 0 To UBound(top)
        report.Append Right("   " & counts(top(i)), 3), "  ", top(i)
        report.AppendLine
    Next
    Print report.ToString;

    ' the document: {"words": n, "different": n, "top": [{"word": .., "count": ..}, ...], "counts": {...}}
    Set doc = CreateObject("Dictionary")
    doc("words") = TotalWords(counts)
    doc("different") = counts.Count
    ReDim list(UBound(top))
    For i = 0 To UBound(top)
        Set entry = CreateObject("Dictionary")
        entry("word") = top(i)
        entry("count") = counts(top(i))
        Set list(i) = entry
    Next
    doc("top") = list
    Set doc("counts") = counts
    json = JsonStringify(doc, 2)
```

`boing run wordfreq.bbp` prints:

```output
Words: 42, different: 26
Most common:
  8  the
  4  amiga
  3  and
  2  future
  2  write
As JSON: [{"word":"the","count":8},{"word":"amiga","count":4},{"word":"and","count":3},{"word":"future","count":2},{"word":"write","count":2}]
(give a file name to save all 26 counts)
```

and `boing run wordfreq.bbp RAM:words.json` saves the whole document, laid out with an indent of
2, in `RAM:words.json`:

```text
{
  "words": 42,
  "different": 26,
  "top": [
    {
      "word": "the",
      "count": 8
    },
    ...
  ],
  "counts": {
    "the": 8,
    "amiga": 4,
    "was": 1,
    ...
  }
}
```

### Gotchas

- `Append` and `AppendLine` return the StringBuilder. Called as a statement
  (`sb.Append "x"`) the result is simply dropped; that is fine.
- `AppendLine` adds a line feed only, the Amiga's line end. For text that must have CR LF line
  ends (some Internet protocols, files for Windows), use `sb.Append x, vbCrLf`.
- `Replace` and `Char` work on bytes and are case-sensitive.

## Regular expressions: RegExp

A *regular expression* is a pattern that describes text: "four digits, a dash, two digits, a
dash, two digits" is `\d{4}-\d\d-\d\d`. With the `RegExp` class you can check whether text
fits a pattern (is this an e-mail address?), find every piece of text that does (the dates in a
log), take those pieces apart (year, month, day) and replace them (turn `2026-11-10` into
`10.11.2026`). Boing BASIC has its own pattern engine, which works the same on AmigaOS 4 and on
the host.

*Listing 20.42* (`examples/book/ch20-libraries/listing-20-42.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp
Set re = CreateObject("RegExp")
re.Pattern = "(\d{4})-(\d\d)-(\d\d)"
re.Global = True
Print re.Replace("from 2026-11-10 to 2026-12-24", "$3.$2.$1")
Print re.Test("no dates here"); re.Test("due 2027-01-31")
```

```output
from 10.11.2026 to 24.12.2026
FalseTrue
```

`CreateObject("RegExp")` makes a new object. Declare the variable `As RegExp`, so that the
compiler checks the member names.

### The RegExp object

| Member | What it does |
|---|---|
| `Pattern` | the regular expression, a String (the default member) |
| `Global` | False (the default): `Execute` and `Replace` stop after the first match. True: they take every match. |
| `IgnoreCase` | True: letters match in either case (A-Z and the accented Latin-1 letters). False at first. |
| `MultiLine` | True: `^` and `$` also match at the start and end of every line, not only of the whole text. False at first. |
| `Test(text)` | True if the pattern matches somewhere in text |
| `Execute(text)` | the matches, as a `Matches` collection (at most one unless `Global` is True) |
| `Replace(text, replacement)` | text with the first match (with `Global`, every match) replaced by replacement, which can contain `$1` and the other forms below |
| `Split(text)` | an array (from 0) of the pieces of text between the matches; the text of any groups in the pattern is included as pieces of its own |
| `FirstMatch(text)` | the text of the first match, `""` if there is none |
| `Escape(text)` | text with a `\` put before every special character (`` \ ^ $ . \| ? * + ( ) [ ] { } / - ``), so that it matches literally |

The pattern is translated into the engine's own form once, and kept until `Pattern`,
`IgnoreCase` or `MultiLine` changes. Using one `RegExp` for every line of a big file is
therefore fast; don't make a new one per line.

### Matches, Match and SubMatches

`Execute` returns a `Matches` collection. Each item is a `Match`, and each `Match` has the texts
of the pattern's groups as its `SubMatches`. All three are read-only, and all count from **0**:

| `Matches` member | |
|---|---|
| `Count` | how many matches |
| `Item(i)` | match number i, from 0. The default member, so `ms(0)` is the first match. |
| `For Each m In ms` | goes through the matches |

| `Match` member | |
|---|---|
| `Value` | the text that matched (the default member, so `Print m` prints it) |
| `FirstIndex` | where it starts in the text, counting from **0**: add 1 for `Mid` |
| `Length` | how long it is |
| `SubMatches` | the texts of the groups: `m.SubMatches(0)` is group 1, `m.SubMatches.Count` how many groups there are; `For Each` works too. A group that took no part in the match is Empty. |
| `SubMatchIndex(i)` | where group i+1 starts (from 0), -1 if it took no part |

Positions from 0 are the one thing to watch: Boing BASIC's string functions (`Mid`, `InStr`)
count from 1.

*Listing 20.43* (`examples/book/ch20-libraries/listing-20-43.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp, m As Variant, ms As Variant, text As String
Set re = CreateObject("RegExp")
re.Pattern = "(\w+)@([\w.]+)"
re.Global = True
text = "write to ann@boing.org or bob@amiga.net"
Set ms = re.Execute(text)
Print ms.Count; " addresses"
For Each m In ms
    Print m.SubMatches(0); " at "; m.SubMatches(1); ", position"; m.FirstIndex; ", length"; m.Length
    Print "  Mid gives: "; Mid(text, m.FirstIndex + 1, m.Length)
Next
Print "the first: "; ms(0); ", its domain from"; ms(0).SubMatchIndex(1)
```

```output
 2  addresses
ann at boing.org, position 9 , length 13 
  Mid gives: ann@boing.org
bob at amiga.net, position 26 , length 13 
  Mid gives: bob@amiga.net
the first: ann@boing.org, its domain from 13 
```

A group that doesn't take part (here, the first alternative when the text is "b") is Empty:

*Listing 20.44* (`examples/book/ch20-libraries/listing-20-44.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp, m As Variant
Set re = CreateObject("RegExp")
re.Pattern = "(a)|(b)"
Set m = re.Execute("b")(0)
Print IsEmpty(m.SubMatches(0)); " ["; m.SubMatches(1); "]"; m.SubMatchIndex(0); m.SubMatchIndex(1)
```

```output
True [b]-1  0 
```

### Pattern syntax

| Pattern | Matches |
|---|---|
| `abc` | the characters themselves |
| `.` | any one character except a line feed |
| `[abc]` `[a-z]` `[^0-9]` | one of the listed characters / one in a range / one that is *not* listed. `\d`, `\w` and `\s` work inside the brackets; a `]` straight after `[` or `[^`, or a `-` at the end, is an ordinary character. |
| `\d` `\w` `\s` | a digit / a word character (a letter, a digit or `_`) / white space (space, tab, CR, LF, form feed, vertical tab) |
| `\D` `\W` `\S` | anything but a digit / a word character / white space |
| `^` `$` | the start / the end of the text (with `MultiLine`: of each line) |
| `\b` `\B` | a word boundary / anywhere but a word boundary |
| `x*` `x+` `x?` | x 0 or more times / 1 or more times / 0 or 1 time, as many as possible ("greedy") |
| `x{n}` `x{n,}` `x{n,m}` | x exactly n times / at least n times / n to m times |
| `x*?` `x+?` `x??` `x{n,m}?` | the same, but as few as possible ("lazy") |
| `a\|b` | a or b |
| `(x)` | a group: repeat it as a whole (`(ab)+`), and remember the text it matched (`$1`, `SubMatches`, `\1`) |
| `(?:x)` | a group that isn't remembered |
| `x(?=y)` `x(?!y)` | x, but only if y follows / doesn't follow (y isn't part of the match) |
| `\1` ... `\9` | the text that group 1 to 9 matched (`(\w)\1` finds a doubled letter) |
| `\n` `\t` `\r` `\f` `\v` `\0` | line feed, tab, carriage return, form feed, vertical tab, the NUL character |
| `\xHH` `\uHHHH` | a character by its code in hexadecimal (up to 255) |
| `\.` `\*` `\\` ... | a special character itself: put `\` before any of `. * + ? ( ) [ ] { } \| ^ $ \` |

A `{` that doesn't start a valid repetition (`a{,2}`, `{x}`) is an ordinary character.

Strings in Boing BASIC are bytes, so a pattern can search binary data too (`\x00+` finds runs of
NUL bytes). Text in Latin-1, as on the Amiga, works with `IgnoreCase` for the accented letters
as well.

Greedy and lazy repetition, a lookahead and a backreference:

*Listing 20.45* (`examples/book/ch20-libraries/listing-20-45.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp
Set re = CreateObject("RegExp")
re.Pattern = "<.+>":  Print re.FirstMatch("<b>bold</b>")    ' greedy: as much as possible
re.Pattern = "<.+?>": Print re.FirstMatch("<b>bold</b>")    ' lazy: as little as possible
re.Pattern = "\w+(?=!)": Print re.FirstMatch("hello there!")
re.Pattern = "\b(\w+) \1\b": Print re.FirstMatch("this is is a typo")
re.Pattern = "^\d{3}-\d{4}$": Print re.Test("555-1234"); re.Test("555-12345")
```

```output
<b>bold</b>
<b>
there
is is
TrueFalse
```

### Options: IgnoreCase and MultiLine

*Listing 20.46* (`examples/book/ch20-libraries/listing-20-46.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp, text As String
Set re = CreateObject("RegExp")
re.Pattern = "amiga"
Print re.Test("AMIGA forever");
re.IgnoreCase = True
Print re.Test("AMIGA forever")

text = "one" & vbLf & "two" & vbLf & "three"
re.Pattern = "^\w+$"
re.Global = True
Print re.Execute(text).Count;          ' the whole text isn't one word
re.MultiLine = True
Print re.Execute(text).Count           ' but each line is
Print re.Replace(text, "* $&")
```

```output
FalseTrue
 0  3 
* one
* two
* three
```

### Replacement text

In the replacement of `Replace`, these forms insert parts of the match:

| Form | Inserts |
|---|---|
| `$1` ... `$99` | the text of that group (`""` if it took no part) |
| `$&` | the whole match |
| ``$` `` | the text before the match |
| `$'` | the text after the match |
| `$$` | a `$` sign |

A `$` followed by anything else, or by the number of a group the pattern doesn't have, is
copied as it is.

*Listing 20.47* (`examples/book/ch20-libraries/listing-20-47.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp
Set re = CreateObject("RegExp")
re.Pattern = "(\w+)@(\w+)"
re.Global = True
Print re.Replace("ann@boing bob@amiga", "$2:$1")
Print re.Replace("ann@boing", "[$$][$&][$`][$'][$3]")
re.Pattern = "\d"
Print re.Replace("a1b2c3", "#")
re.Global = False
Print re.Replace("a1b2c3", "#")         ' only the first
re.Global = True
re.Pattern = "\s+"
Print re.Replace("too    many     spaces", " ")
```

```output
boing:ann amiga:bob
[$][ann@boing][][][$3]
a#b#c#
a#b2c3
too many spaces
```

### Split and Escape

`Split` cuts the text at every match of the pattern, which here is "a comma or semicolon, with
any spaces around it". `Escape` makes a pattern out of text that should be found literally, for
example something the user typed into a search field:

*Listing 20.48* (`examples/book/ch20-libraries/listing-20-48.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp, parts As Variant
Set re = CreateObject("RegExp")
re.Pattern = "\s*[,;]\s*"
parts = re.Split("apples, pears;plums ,  cherries")
Print UBound(parts) + 1; " pieces: "; Join(parts, "|")
re.Pattern = "(-)"                      ' a group: the dashes are pieces too
Print Join(re.Split("1-2-3"), "|")

Print re.Escape("1+1=2? (yes) $5.00")
re.Pattern = re.Escape("1+1=2?")
Print re.Test("is 1+1=2?"); re.Test("11=2")
```

```output
 4  pieces: apples|pears|plums|cherries
1|-|2|-|3
1\+1=2\? \(yes\) \$5\.00
TrueFalse
```

### Errors

| `Err.Number` | Meaning |
|---|---|
| 5017 | the pattern is wrong; `Err.Description` says what is wrong ("missing )", "nothing to repeat before *, + or ?"...) |
| 5019 | the pattern needs too much backtracking on this text: the engine gives up after 50 million steps instead of running practically for ever |
| 9 | an `Item` or `SubMatches` index out of range |
| 383 | assigning to a member of `Matches`, `Match` or `SubMatches` (they are read-only) |

The pattern is checked when it is first used (`Test`, `Execute`...), not when `Pattern` is set.

*Listing 20.49* (`examples/book/ch20-libraries/listing-20-49.bas`)

<!-- run -->
```basic
Option Explicit
Dim re As RegExp, bad As Variant, ok As Boolean
Set re = CreateObject("RegExp")
On Error Resume Next
For Each bad In Array("(", "[a", "*a", "a{3,2}", "\2(a)")
    re.Pattern = bad
    ok = re.Test("x")
    Print bad; " -> "; Err.Number; " "; Err.Description
    Err.Clear
Next
re.Pattern = "(x+x+)+y"
ok = re.Test(String(40, "x"))
Print "(x+x+)+y -> "; Err.Number; " "; Err.Description
```

```output
( ->  5017  bad regular expression: missing )
[a ->  5017  bad regular expression: missing ] in a character class
*a ->  5017  bad regular expression: nothing to repeat before *, + or ?
a{3,2} ->  5017  bad regular expression: {n,m} with m < n
\2(a) ->  5017  bad regular expression: a backreference to a group that doesn't exist
(x+x+)+y ->  5019  the regular expression takes too long on this text (too much backtracking)
```

A pattern such as `(x+x+)+y` has a vast number of ways to try to match a long run of `x` with
no `y` after it, and tries all of them before it fails. Write patterns where each part of the
text can be matched in only one way (`x+y` here), and error 5019 never comes up.

### Example: a log analyser

The book example `examples/book/ch20-libraries/loganalyser` reads a program's log file, with
lines like

```text
2026-11-10 12:01:33 [Http] ERROR: timeout after 30000 ms (www.example.com)
```

and reports how many lines of each level it has, which modules reported errors, the time span
and the hosts that timed out. One pattern takes every line apart; its groups are the date, the
time, the module, the level and the message:

*Listing 20.50* (`examples/book/ch20-libraries/loganalyser/loganalyser.bbp`)

<!-- project: examples/book/ch20-libraries/loganalyser/loganalyser.bbp -->
```basic
' loganalyser.bas - a summary of a log file, with regular expressions
Option Explicit

Dim lineRe As RegExp, hostRe As RegExp
Dim levels(1 To 4) As String, counts(1 To 4) As Long
Dim modules As String, hosts As String, first As String, last As String
Dim f As Integer, text As String, total As Long, skipped As Long

' a list in a String: "|Http|Disk|"; add a name once
Sub AddOnce(list As String, ByVal name As String)
    If list = "" Then list = "|"
    If InStr(list, "|" & name & "|") = 0 Then list = list & name & "|"
End Sub

Function ListText(ByVal list As String) As String
    If list = "" Then ListText = "(none)" Else ListText = Replace(Mid(list, 2, Len(list) - 2), "|", ", ")
End Function

Sub Tally(ByVal level As String)
    Dim i As Long
    For i = 1 To 4
        If levels(i) = UCase(level) Then counts(i) = counts(i) + 1: Exit Sub
    Next
End Sub

Sub Main()
    Dim m As Variant, i As Long
    levels(1) = "DEBUG": levels(2) = "INFO": levels(3) = "WARN": levels(4) = "ERROR"

    Set lineRe = CreateObject("RegExp")
    lineRe.Pattern = "^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d) \[(\w+)\] (DEBUG|INFO|WARN|ERROR): (.*)$"
    lineRe.IgnoreCase = True                ' "error:" and "Error:" too
    Set hostRe = CreateObject("RegExp")
    hostRe.Pattern = "timeout .*\(([\w.-]+)\)"

    f = FreeFile
    Open "app.log" For Input As #f
    Do Until EOF(f)
        Line Input #f, text
        If lineRe.Test(text) Then
            Set m = lineRe.Execute(text)(0)
            total = total + 1
            If first = "" Then first = m.SubMatches(0) & " " & m.SubMatches(1)
            last = m.SubMatches(0) & " " & m.SubMatches(1)
            Tally m.SubMatches(3)
            If UCase(m.SubMatches(3)) = "ERROR" Then
                AddOnce modules, m.SubMatches(2)
                If hostRe.Test(m.SubMatches(4)) Then AddOnce hosts, hostRe.Execute(m.SubMatches(4))(0).SubMatches(0)
            End If
        ElseIf Trim(text) <> "" Then
            skipped = skipped + 1           ' a line in another format (a stack dump...)
        End If
    Loop
    Close #f

    Print total & " log lines from " & first & " to " & last & ", " & skipped & " other lines"
    For i = 1 To 4
        Print "  " & levels(i) & ": " & counts(i)
    Next
    Print "errors from: "; ListText(modules)
    Print "timeouts at: "; ListText(hosts)
End Sub
```

With the sample `app.log` from the example's drawer, it prints:

```output
12 log lines from 2026-11-10 09:14:02 to 2026-11-10 10:03:00, 2 other lines
  DEBUG: 1
  INFO: 5
  WARN: 2
  ERROR: 4
errors from: Http, Disk
timeouts at: www.example.com, feeds.amiga.org
```

### Limits

Not supported: lookbehind (`(?<=...)`, `(?<!...)`), named groups, and Unicode character
classes (strings are bytes; text in UTF-8 can be searched, but `.` and `\w` see bytes, not
characters).

The engine is a backtracking matcher. Its stack is on the heap, so a deep pattern can't
overflow the AmigaOS stack of your program, and the step limit (error 5019) stops a pattern
that would otherwise hang. A pattern that starts with a plain character jumps from one
occurrence of that character to the next, so searching a long text for `needle\d+` is quick.

## CSV files: Csv

CSV ("comma-separated values") is the plain-text table format that spreadsheets, databases and
many web services use to exchange data: one record per line, fields separated by commas, and
usually a first line with the column names.

```text
name,age,city
Ann,34,"Bonn, Germany"
"Bob ""B"" Smith",41,
```

Splitting each line at the commas works until the data has a comma, a quote or a line break
inside a field, and real data always does. The `Csv` class handles all of that: fields in
quotes, `""` for a quote inside them, line breaks inside quoted fields, other separators (`;`,
tab), header rows, and Windows, Unix and old Mac line ends. It reads and writes.

*Listing 20.51* (`examples/book/ch20-libraries/listing-20-51.bas`)

<!-- run -->
```basic
Option Explicit
Dim table As Csv
Set table = CreateObject("Csv")
table.HasHeader = True
table.LoadText "name,age,city" & vbLf & _
               "Ann,34,""Bonn, Germany""" & vbLf & _
               """Bob """"B"""" Smith"",41,"
Do While table.ReadRecord()
    Print table.Field("name"); " is "; table.Field("age"); " ["; table.Field("city"); "]"
Loop
```

```output
Ann is 34 [Bonn, Germany]
Bob "B" Smith is 41 []
```

Give the variable a name other than `csv`. Names in Boing BASIC aren't case-sensitive, so
`Dim csv As Csv` would make the variable hide the type `Csv`. `table`, `reader` or `out` are
good names.

### Reading

Open a file with `Open` (or give the text itself to `LoadText`), then call `ReadRecord` until
it returns False. After each `ReadRecord`, the current record's fields are there to read.

| Member | What it does |
|---|---|
| `Open path` | reads a file (all of it, into memory) for `ReadRecord`. Error 53 if it isn't there. |
| `LoadText text` | the same, from a String |
| `ReadRecord()` | moves to the next record; returns False at the end. Empty lines are skipped. |
| `Field(index)`, `Field(name)` | a field of the current record: by its position, counting from **0**, or by its column name (needs `HasHeader`; the case of the name doesn't matter). `Field` is the default member, so `table("name")` works too. A field the record doesn't have is `""`. |
| `Fields` | the current record as an array of Strings, from 0 |
| `FieldCount` | how many fields the current record has |
| `Headers` | the column names (the first record) as an array, with `HasHeader` |
| `ColumnIndex(name)` | the position of a column (from 0), -1 if there is none |
| `ReadAll()` | all the remaining records as a two-dimensional array `a(record, field)`, both from 0. Records with fewer fields are padded with `""`. |
| `RecordNumber` | the current record's number: 1 for the first record after the header |
| `LineNumber` | the line of the text where the current record starts (a quoted field can span lines, so this can differ from `RecordNumber`) |
| `AtEnd` | True when no records are left |
| `ParseLine(text)` | the fields of one record, given as text, as an array (no file needed) |

All fields are Strings, as they are in the file. Convert numbers and dates with `Val`, `CLng`,
`CDbl` or `CDate` where you need them.

*Listing 20.52* (`examples/book/ch20-libraries/listing-20-52.bas`)

<!-- run -->
```basic
Option Explicit
Dim table As Csv, h As Variant, total As Double
Set table = CreateObject("Csv")
table.HasHeader = True
table.LoadText "Item,Price,Note" & vbCrLf & _
               "Disk box,4.50,""holds 50""" & vbCrLf & _
               "Mouse mat,3.25,""blue," & vbLf & "with Boing ball""" & vbCrLf & _
               vbCrLf & _
               "Joystick,19.99"
For Each h In table.Headers
    Print "["; h; "]";
Next
Print "  price is column"; table.ColumnIndex("PRICE")
Do While table.ReadRecord()
    Print table.RecordNumber; table.LineNumber; table.FieldCount; " "; table(0); ": "; _
          Replace(table.Field("Note"), vbLf, " / ")
    total = total + Val(table.Field("Price"))
Loop
Print "total"; total; " at end: "; table.AtEnd
```

```output
[Item][Price][Note]  price is column 1 
 1  2  3  Disk box: holds 50
 2  3  3  Mouse mat: blue, / with Boing ball
 3  6  2  Joystick: 
total 27.74  at end: True
```

`ReadAll` takes the rest of the records in one go. Here the first line isn't a header, so it
comes back as record 0:

*Listing 20.53* (`examples/book/ch20-libraries/listing-20-53.bas`)

<!-- run -->
```basic
Option Explicit
Dim table As Csv, a As Variant, r As Long, c As Long
Set table = CreateObject("Csv")
table.LoadText "a,b,c" & vbLf & "1,2" & vbLf & "x,y,z"
a = table.ReadAll()
Print UBound(a, 1) + 1; " records of"; UBound(a, 2) + 1; " fields"
For r = 0 To UBound(a, 1)
    For c = 0 To UBound(a, 2)
        Print "["; a(r, c); "]";
    Next
    Print
Next
```

```output
 3  records of 3  fields
[a][b][c]
[1][2][]
[x][y][z]
```

`ParseLine` is handy for one line of CSV that comes from somewhere else, a network message for
example:

*Listing 20.54* (`examples/book/ch20-libraries/listing-20-54.bas`)

<!-- run -->
```basic
Option Explicit
Dim table As Csv, f As Variant
Set table = CreateObject("Csv")
f = table.ParseLine("42,""Smith, John"",""said """"hi""""""")
Print UBound(f) + 1; " fields: "; Join(f, " | ")
```

```output
 3  fields: 42 | Smith, John | said "hi"
```

### Writing

| Member | What it does |
|---|---|
| `Create path [, append]` | opens a file for writing; with append True, records are added to the end of an existing file |
| `WriteRecord value, value, ...` | writes one record: each argument is a field, or give one array whose elements are the fields. With no file open, the record is added to `Text` instead. |
| `FormatRecord(value, ...)` | the record as a String (without a line end), written nowhere |
| `Text` | what `WriteRecord` wrote while no file was open; `Text = ""` empties it |
| `Close` | closes the file (the one from `Create`, or the input of `Open`) |

Numbers, dates and Booleans are written the way `CStr` writes them (`3.5`, `True`); Empty and
Null become empty fields. A field is put in quotes only when it has to be: when it contains the
delimiter, a quote or a line break, or starts or ends with a space. A quote inside it is
written as `""`.

*Listing 20.55* (`examples/book/ch20-libraries/listing-20-55.bas`)

<!-- run -->
```basic
Option Explicit
Dim out As Csv
Set out = CreateObject("Csv")
Print out.FormatRecord("plain", "with,comma", "with ""quote""", " space", 3.5, True, Null)
out.WriteRecord "id", "text"
out.WriteRecord 1, "a, b"
out.WriteRecord Array(2, "c")
Print out.Text;
out.QuoteAll = True
Print out.FormatRecord(Array("a", 1, Empty))
```

```output
plain,"with,comma","with ""quote"""," space",3.5,True,
id,text
1,"a, b"
2,c
"a","1",""
```

Writing a file and reading it back. Note that a field with a line break in it survives the trip
intact:

*Listing 20.56* (`examples/book/ch20-libraries/listing-20-56.bas`)

<!-- run -->
```basic
Option Explicit
Dim out As Csv, table As Csv, i As Long
Set out = CreateObject("Csv")
out.Create "scores.csv"
out.WriteRecord "Player", "Score", "Comment"
out.WriteRecord "Ann", 1200, "first place"
out.WriteRecord "Bob", 950, "lost a life on" & vbLf & "level 3"
out.Close
out.Create "scores.csv", True           ' append
out.WriteRecord "Cy", 700, ""
out.Close

Set table = CreateObject("Csv")
table.HasHeader = True
table.Open "scores.csv"
Do While table.ReadRecord()
    Print table("Player"); CLng(table("Score")) * 2; " "; Replace(table("Comment"), vbLf, "\n")
Loop
table.Close
Kill "scores.csv"
```

```output
Ann 2400  first place
Bob 1900  lost a life on\nlevel 3
Cy 1400  
```

### Settings

| Property | Default | What it sets |
|---|---|---|
| `Delimiter` | `","` | the field separator, one character: `";"` (common in Germany and France, where the comma is the decimal point), `vbTab` |
| `Quote` | `""""` (a `"`) | the quote character; `""` for none, and quotes are then ordinary characters |
| `HasHeader` | False | the first record holds the column names (`Headers`, `Field(name)`) |
| `TrimFields` | False | remove spaces and tabs around fields when reading |
| `QuoteAll` | False | put every field in quotes when writing |
| `LineEnding` | `vbLf` | what is written after each record; `vbCrLf` for programs on other systems that want it |

When reading, LF, CR LF and CR line ends are all understood, and a UTF-8 byte order mark at the
start of the text is skipped. The text isn't converted: a file in UTF-8 gives UTF-8 Strings.

*Listing 20.57* (`examples/book/ch20-libraries/listing-20-57.bas`)

<!-- run -->
```basic
Option Explicit
Dim table As Csv
Set table = CreateObject("Csv")
table.Delimiter = ";"
table.LoadText "1; 2 ;3" & vbLf & "a;""b;c"";d"
table.ReadRecord: Print Join(table.Fields, "|")
table.ReadRecord: Print Join(table.Fields, "|")
table.TrimFields = True
table.LoadText "1; 2 ;3"
table.ReadRecord: Print Join(table.Fields, "|")
```

```output
1| 2 |3
a|b;c|d
1|2|3
```

### Errors

| `Err.Number` | Meaning |
|---|---|
| 53 | `Open`: the file isn't there |
| 57 | the file can't be read |
| 75 | `Create`: the file can't be created |
| 61 | writing failed (the disk is full) |
| 380 | a bad `Delimiter` or `Quote`: more than one character, or both the same |
| 5 | `Field` with a column name that doesn't exist (`Err.Description` names it) |
| 9 | a negative field index |

*Listing 20.58* (`examples/book/ch20-libraries/listing-20-58.bas`)

<!-- run -->
```basic
Option Explicit
Dim table As Csv, s As String
Set table = CreateObject("Csv")
On Error Resume Next
table.Delimiter = ",,"
Print "delimiter:"; Err.Number: Err.Clear
table.Open "no such file.csv"
Print "open:"; Err.Number: Err.Clear
table.HasHeader = True
table.LoadText "a,b" & vbLf & "1,2"
table.ReadRecord
s = table.Field("c")
Print "column:"; Err.Number; " "; Err.Description: Err.Clear
Print "missing field: ["; table.Field(5); "]"; Err.Number
```

```output
delimiter: 380 
open: 53 
column: 5  no column named c
missing field: [] 0 
```

## Unique identifiers: CreateUUID

`CreateUUID()` returns a new, random UUID ("universally unique identifier"): 36 characters of
hexadecimal digits in lower case, with dashes, such as `3f2b8c1e-9d4a-4e7b-a5c2-0d8e6f1b2a93`.

| Function | Returns |
|---|---|
| `CreateUUID()` | a new random UUID (version 4), as a String of 36 characters |

Use one when a record, a file or a message needs a name that nobody else will ever pick: keys
for database records made on several machines, names for temporary files, session numbers
for a network protocol. Each call gives a different value; the chance of two UUIDs ever being
the same is negligible (122 of their 128 bits are random).

The form is always `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`: the `4` marks a random UUID
(version 4), and `y` is one of `8`, `9`, `a` or `b` (the standard variant, RFC 4122). So a
program can check that a String looks like one of its UUIDs:

*Listing 20.59* (`examples/book/ch20-libraries/listing-20-59.bas`)

<!-- run -->
```basic
Option Explicit
Dim id As String, other As String
id = CreateUUID()
other = CreateUUID()
Print Len(id); id Like "????????-????-4???-????-????????????"; InStr("89ab", Mid(id, 20, 1)) > 0
Print "different:"; id <> other
```

```output
 36 TrueTrue
different:True
```

Where the random numbers come from: on AmigaOS the generator is seeded from the EClock, the
time and memory addresses, and stirred again from the clock on every call; on the host it uses
the system's random source (`/dev/urandom`). That is good for identifiers. For passwords and
encryption keys, use a cryptographic random source instead.

## Running commands: Process

`Process` runs a Shell command, waits until it has finished, and gives you what it printed and
its return code. It also reads and sets environment variables. With it, a program can use the
commands AmigaOS already has (`List`, `Search`, `Version`, `LhA`, ...) and work with their
results.

*Listing 20.60* (`examples/book/ch20-libraries/listing-20-60.bas`)

```basic
Option Explicit
Dim p As Process
Set p = CreateObject("Process")
If p.Run("Version") = 0 Then Print "This is "; p.Output
```

`Shell` ([chapter 10](10-files.md)) runs a command and waits for it too, but gives you only its
return code: what the command prints goes to the console. Use `Process` when you need the
output.

### Running a command

| Member | What it does |
|---|---|
| `Run(command [, input])` | runs the command line and waits until it has finished. input, if you give it, is what the command reads as its input. Returns the exit code. |
| `Output` | what the command wrote to its standard output (the default member) |
| `ErrorOutput` | what it wrote to its error output |
| `OutputLines()` | `Output` split into lines, as an array from 0 (LF or CR LF line ends; no empty last element for the final line end) |
| `ExitCode` | the last command's exit code |
| `CommandLine` | the last command line |

`Output`, `ErrorOutput`, `ExitCode` and `CommandLine` are read-only (error 383), and keep their
values until the next `Run`. `Run` can also be used as a statement when you don't need the exit
code at once: `p.Run "Delete T:old#?"`.

The command goes to the system's shell. On AmigaOS that is the user shell, so aliases, the
`Path`, `$variables`, redirection and several commands in one String, separated by line feeds,
all work. On the host it is `/bin/sh -c`.

*Listing 20.61* (`examples/book/ch20-libraries/listing-20-61.bas`)

<!-- run -->
```basic
Option Explicit
Dim p As Process, rc As Long
Set p = CreateObject("Process")
rc = p.Run("echo hello world")
Print "exit code"; rc; ", output ["; Replace(p.Output, vbLf, "\n"); "]"
Print "the command was: "; p.CommandLine
```

```output
exit code 0 , output [hello world\n]
the command was: echo hello world
```

**Exit codes.** On AmigaOS the exit code is the command's return code: 0 for OK, 5 WARN, 10
ERROR, 20 FAIL. `Search`, for example, returns 5 when it finds nothing. On the host it is the program's exit status (127: the command
wasn't found).

A command that starts but fails is not a run-time error: check the exit code, and look at
`ErrorOutput` for the message.

*Listing 20.62* (`examples/book/ch20-libraries/listing-20-62.bas`)

```basic
Option Explicit
Dim p As Process
Set p = CreateObject("Process")
If p.Run("Search S: Boing QUIET") = 5 Then
    Print "No file in S: mentions Boing"
End If
If p.Run("Type nonexistent-file") <> 0 Then
    Print "Type failed with"; p.ExitCode; ": "; p.Output; p.ErrorOutput
End If
```

**Output line by line.** `OutputLines` gives an array to go through with `For Each`:

*Listing 20.63* (`examples/book/ch20-libraries/listing-20-63.bas`)

```basic
Option Explicit
Dim p As Process, f As Variant
Set p = CreateObject("Process")
p.Run "List RAM: FILES LFORMAT %N"          ' the names of the files in RAM:, one per line
For Each f In p.OutputLines()
    Print "file: "; f
Next
```

**Input.** The second argument of `Run` is what the command reads as its input. On AmigaOS
that is the command's `Input()` stream: what a command reads when it asks for its arguments
with `?`, or when it reads from its standard input. `Echo ?` asks for Echo's arguments, so it
echoes the input back:

*Listing 20.64* (`examples/book/ch20-libraries/listing-20-64.bas`)

```basic
Option Explicit
Dim p As Process
Set p = CreateObject("Process")
p.Run "Echo ?", "hello" & vbLf
Print p.Output
```

Give each line of input its line end (`vbLf`), as if someone typed it. Some commands read the
console window directly instead of their input, and don't see this text.

**How the output is collected.** On AmigaOS the output is written to files in `T:` while the
command runs, and read when it has finished; on the host it comes through pipes. Either way the
whole output is kept in memory, so a command that prints megabytes needs megabytes of memory.
The program waits while the command runs; in a form program, the window doesn't respond
meanwhile, so run long commands with care.

### Environment variables

| Member | What it does |
|---|---|
| `GetEnv(name)` | the value of a variable, `""` if it isn't set (the same as `Environ(name)`) |
| `SetEnv name, value` | sets a variable for this program and the commands it runs. `SetEnv name` with no value, or with `""`, removes it. On AmigaOS this is a *local* variable (one of the program's shell, as the `Set` command makes), never a global one in `ENV:`. Error 5 for a name that can't be used. |
| `Environment()` | all the variables, as an array of `"NAME=value"` Strings from 0. On AmigaOS: the local variables first, then the global ones in `ENV:` (only the top level, not the drawers inside it). |

`Environ(n)` ([chapter 10](10-files.md)), with n counting from 1, gives the same list one
entry at a time.

*Listing 20.65* (`examples/book/ch20-libraries/listing-20-65.bas`)

<!-- run -->
```basic
Option Explicit
Dim p As Process, v As Variant, found As Boolean
Set p = CreateObject("Process")
p.SetEnv "BOING_GREETING", "hello from Boing"
Print "GetEnv: "; p.GetEnv("BOING_GREETING")
Print "Environ: "; Environ("BOING_GREETING")
For Each v In p.Environment()
    If v = "BOING_GREETING=hello from Boing" Then found = True
Next
Print "in Environment():"; found
p.Run "echo $BOING_GREETING"                ' the command sees it too
Print "the command printed: "; p.OutputLines()(0)
p.SetEnv "BOING_GREETING"                   ' removed
Print "removed: ["; p.GetEnv("BOING_GREETING"); "]"
```

```output
GetEnv: hello from Boing
Environ: hello from Boing
in Environment():True
the command printed: hello from Boing
removed: []
```

### Errors

| `Err.Number` | Meaning |
|---|---|
| 31201 | the command couldn't be started at all (no shell, or on AmigaOS `T:` isn't writable) |
| 5 | `SetEnv` with a name that can't be used |
| 383 | assigning to `Output`, `ErrorOutput`, `ExitCode` or `CommandLine` |

## IniFile: settings files

An INI file is the plain-text settings format with `[sections]` and `key=value` lines:

```ini
; Tincture settings
[Window]
Width=640
Height=480

[Recent]
File1=Work:Pictures/sunset.iff
```

`IniFile` reads and writes such files. Use it for a program's preferences, a game's options or
a tool's configuration. The user can open the file in any text editor and change it, and when
your program saves its own changes, `IniFile` keeps the user's comments, blank lines, spacing
and order exactly as they were.

You make one with `CreateObject`:

<!-- fragment -->
```basic
Dim prefs As IniFile
Set prefs = CreateObject("IniFile")
prefs.Load "PROGDIR:Tincture.ini"            ' a missing file is simply empty
```

### Reading values

`Value(section, key [, default])` returns a value as a String. If the section or the key is not
there, you get the default, or `""` if you gave none. `Value` is the default member, so
`prefs("Window", "Width")` is the same as `prefs.Value("Window", "Width")`.

| Member | What it does |
|---|---|
| `Load path [, mustExist]` | reads a file and remembers its name for `Save`. Returns True if the file was there. A missing file gives an empty `IniFile` and returns False; with `mustExist` = True it is error 53 instead. |
| `LoadText text` | reads the settings from a String instead of a file |
| `Value(section, key [, default])` | a value as a String, or the default (`""` if none) when it isn't there |
| `Sections` | the section names, as an array of Strings. `""` comes first if there are keys before the first section. |
| `Keys(section)` | the key names of a section, as an array. A section that isn't there gives an empty array (`UBound` is -1). |
| `HasSection(section)` | True if the section is there |
| `HasKey(section, key)` | True if the key is there |

The rules of the format:

- Names of sections and keys are not case-sensitive: `Value("video", "WIDTH")` finds `Width` in
  `[Video]`.
- Spaces around keys and values are ignored. To keep spaces at the ends of a value, put it in
  double quotes: `Name="  x  "` gives `  x  `.
- Lines that start with `;` or `#` are comments.
- Keys before the first `[section]` line belong to the section `""`.
- Every value is text. Read numbers with `CLng`, `CDbl` or `Val`:
  `w = CLng(prefs.Value("Window", "Width", "640"))`.

### Changing and saving

| Member | What it does |
|---|---|
| `Value(section, key) = value` | sets a value. A new key goes after the last key of its section; a new section goes at the end of the file. A number is written the way `CStr` writes it. |
| `DeleteKey(section, key)` | removes a key; returns True if it was there |
| `DeleteSection(section)` | removes a section with all its keys and comments; returns True if it was there |
| `Clear` | empties everything |
| `Save [path]` | writes the file: to `path`, or to the file it was loaded from |
| `Text` | the whole file as a String. Assigning to it is the same as `LoadText`. |
| `Path` | the file name `Save` writes to (set by `Load`; you can also assign it) |
| `Changed` | True if something was changed since the last `Load` or `Save` |

`Save` writes every line your program did not change exactly as it was. A file with CR LF line
ends (written on another computer) keeps them. Setting a value to the same text it already has
is not a change.

### Example: a run counter

This program keeps a settings file in the current directory. It counts how often it has run,
remembers a user name, and reads a value with a default. It then lists what the file contains,
and deletes it at the end, so that it prints the same every time.

*Listing 20.66* (`examples/book/ch20-libraries/listing-20-66.bas`)

<!-- run -->
```basic
Option Explicit
Dim prefs As IniFile, s As Variant, k As Variant, runs As Long, i As Long

Set prefs = CreateObject("IniFile")
' start from a file with a comment in it, written by "the user"
prefs.LoadText "; settings for the counter" & vbLf & "[User]" & vbLf & "Name = Ann" & vbLf
prefs.Save "counter.ini"

For i = 1 To 3                                 ' three "runs" of the program
    Set prefs = CreateObject("IniFile")
    If Not prefs.Load("counter.ini") Then Print "first run"
    runs = CLng(prefs.Value("Stats", "Runs", "0")) + 1
    prefs.Value("Stats", "Runs") = runs
    prefs.Save
Next

Print "Hello "; prefs("User", "Name"); ", run"; runs
Print "Colour: "; prefs.Value("User", "Colour", "blue")
For Each s In prefs.Sections
    For Each k In prefs.Keys(s)
        Print "["; s; "] "; k; " = "; prefs.Value(s, k)
    Next
Next
Print "---"
Print prefs.Text;
Kill "counter.ini"
```

```output
Hello Ann, run 3 
Colour: blue
[User] Name = Ann
[Stats] Runs = 3
---
; settings for the counter
[User]
Name = Ann

[Stats]
Runs=3
```

The comment and the spaces in `Name = Ann` are still there after three saves; the new section
`[Stats]` was added at the end (with a blank line before it).

A real program loads its settings once when it starts and saves them when it ends, or when the
user closes a preferences window:

<!-- fragment -->
```basic
Private Sub Form_Load()
    Set prefs = CreateObject("IniFile")
    prefs.Load "PROGDIR:Tincture.ini"
    Me.Width = CLng(prefs("Window", "Width", "640"))
    Me.Height = CLng(prefs("Window", "Height", "480"))
End Sub

Private Sub Form_Unload(Cancel As Integer)
    prefs("Window", "Width") = Me.Width
    prefs("Window", "Height") = Me.Height
    If prefs.Changed Then prefs.Save
End Sub
```

### IniFile or GetSetting?

`GetSetting` and `SaveSetting` (chapter 10) keep each value in its own small file in the
system's settings drawer (`ENVARC:`). They need no file name and no object, so they are the
quickest way to remember a few values, but the user doesn't usually look there or edit them.

Use an `IniFile` when the settings should be one readable file that the user can edit, copy or
back up: next to the program (`PROGDIR:`), in `ENVARC:`, or on a USB stick. It is also the
right choice for reading configuration files written by other programs.

### Errors and limits

| Error | When |
|---|---|
| 53 | `Load` with `mustExist` = True and the file isn't there |
| 75 | `Save` can't create the file |
| 61 | writing failed (for example, the disk is full) |
| 5 | a bad key or section name, a value with a line break in it, or `Save` without a file name (nothing was loaded and no path given) |

A key can't contain `=` or start with `[`, `;` or `#`; a section name can't contain `]`. A value
is one line: it can't contain line breaks.

*Listing 20.67* (`examples/book/ch20-libraries/listing-20-67.bas`)

<!-- run -->
```basic
Option Explicit
Dim ini As IniFile
Set ini = CreateObject("IniFile")
On Error Resume Next
ini.Value("Game", "lives=3") = 1
Print "bad key:"; Err.Number: Err.Clear
ini.Value("Game", "Title") = "two" & vbLf & "lines"
Print "line break:"; Err.Number: Err.Clear
ini.Load "no-such-file.ini", True
Print "must exist:"; Err.Number: Err.Clear
Set ini = CreateObject("IniFile")
ini.Save
Print "no name:"; Err.Number
```

```output
bad key: 5 
line break: 5 
must exist: 53 
no name: 5 
```

## Logger: logging

A log is a file in which a program writes what it is doing: when it started, what it loaded,
what went wrong. When a user reports a problem, the log tells you what happened. `Logger`
writes such messages, each on its own line with the date, the time and a level, to a log file
or to the console.

Every message has a level, from Debug (details for you while you develop) to Fatal (the program
can't go on). The logger writes only the messages at or above its `Level`, so you can leave the
debug messages in the program and switch them on when you need them.

<!-- fragment -->
```basic
Dim lg As Logger
Set lg = CreateObject("Logger")
lg.FileName = "PROGDIR:Downloader.log"
lg.Info "started"
lg.Debug "url = " & url              ' only written when Level is logDebug
lg.Error "can't save " & path & ": " & Err.Description
```

`PROGDIR:Downloader.log` then holds lines like these (the debug message is not there, because
the level is `logInfo` unless you change it):

```text
2026-11-10 14:03:21 INFO started
2026-11-10 14:03:25 ERROR can't save RAM:x.lha: Disk full
```

### Writing messages

| Method | Level | Constant |
|---|---|---|
| `Debug message` | 10 | `logDebug` |
| `Info message` | 20 | `logInfo` |
| `Warning message` | 30 | `logWarning` |
| `Error message` | 40 | `logError` |
| `Fatal message` | 50 | `logFatal` |
| `Log level, message` | any level from 0 to 99 | |

A message is written when its level is at least `Level`. Set `Level` to `logOff` (100) to write
nothing at all. With `Log` you can use levels in between: the `{level}` field shows the nearest
named level below it, so `Log 35, "..."` is shown as WARNING, and levels under 10 as DEBUG.

`Fatal` only writes the message: it does not end the program. Call `End` yourself if you need to.

### Settings

| Property | Default | What it does |
|---|---|---|
| `Level` | `logInfo` | the lowest level that is written; `logOff` writes nothing |
| `FileName` | `""` | the log file. Messages are added to the end of it; the file is opened at the first message. Empty: messages go to the console instead. |
| `Console` | False | with a `FileName`, also write every message to the console |
| `Pattern` | `{date} {time} {level} {message}` | the layout of a line (see below) |
| `Source` | `""` | a name shown by `{source}`, such as the module or the part of the program that logs |
| `MaxSize` | 0 | the largest size of the log file, in bytes. When a line would make the file larger, the file is renamed to *name*`.old` (replacing an older one) and a new file is started. 0 means no limit. |
| `AutoFlush` | True | write each line to the disk at once, so that a crash or a reset doesn't lose the last messages. Set it to False for speed when you log a lot, and call `Flush`. |

The console is the program's standard error output: the Shell window the program was started
from.

#### The pattern

`Pattern` is the text of each line, with fields in braces that the logger fills in:

| Field | Shows |
|---|---|
| `{date}` | the date, as 2026-11-10 |
| `{time}` | the time, as 14:03:21 |
| `{ms}` | the milliseconds (000-999) |
| `{level}` | DEBUG, INFO, WARNING, ERROR or FATAL |
| `{source}` | the `Source` property |
| `{message}` | the message |
| `{line}` | the program line that logged the message. This works in compiled (native) programs; in the interpreter it shows 0. |

Anything else in the pattern is copied as it is. For example `"{time}.{ms} [{source}] {message}"`
gives lines like `14:03:21.482 [net] connected`.

### Other members

| Member | What it does |
|---|---|
| `Count` | the number of messages written so far (messages below `Level` don't count) |
| `LastMessage` | the last line written, without the line end |
| `Flush` | write buffered lines to the disk (only needed with `AutoFlush` = False) |
| `Close` | close the log file. The next message opens it again. Assigning `FileName` closes the old file too. |

### Example: levels and a log file

This program logs to a file in the current directory with a pattern without the date and time
(so that the output is the same every time), changes the level, and then prints the file.

*Listing 20.68* (`examples/book/ch20-libraries/listing-20-68.bas`)

<!-- run -->
```basic
Option Explicit
Dim lg As Logger, s As String

Set lg = CreateObject("Logger")
lg.FileName = "example.log"
lg.Pattern = "{level} [{source}] {message}"
lg.Source = "main"

lg.Info "program started"
lg.Debug "not written: the level is logInfo"
lg.Level = logDebug
lg.Debug "now debug messages are written"
lg.Source = "loader"
lg.Warning "no settings file, using the defaults"
lg.Log 45, "between Error and Fatal"
lg.Level = logError
lg.Info "not written: the level is logError"
lg.Error "can't open the picture"
Print lg.Count; "messages, the last: "; lg.LastMessage
lg.Close

Open "example.log" For Input As #1
Do Until EOF(1)
    Line Input #1, s
    Print s
Loop
Close #1
Kill "example.log"
```

```output
 5 messages, the last: ERROR [loader] can't open the picture
INFO [main] program started
DEBUG [main] now debug messages are written
WARNING [loader] no settings file, using the defaults
ERROR [loader] between Error and Fatal
ERROR [loader] can't open the picture
```

### Example: a log that doesn't grow for ever

A program that runs for a long time (a server, a downloader) can fill a disk with its log. With
`MaxSize` the file is kept small: when it is full, it becomes *name*`.old` and a new file starts,
so there are never more than two files of at most `MaxSize` bytes. (The file is rotated before
a line that wouldn't fit, so lines are never split: at the end, `server.log.old` holds nine
lines of 32 bytes, and `server.log` the last three.)

*Listing 20.69* (`examples/book/ch20-libraries/listing-20-69.bas`)

<!-- run -->
```basic
Option Explicit
Dim lg As Logger, i As Long

Set lg = CreateObject("Logger")
lg.FileName = "server.log"
lg.Pattern = "{level} {message}"
lg.MaxSize = 300
For i = 1 To 30
    lg.Info "request number " & i & " answered"
Next
lg.Close
Print "server.log:"; FileLen("server.log"); "bytes"
Print "server.log.old:"; FileLen("server.log.old"); "bytes"
Kill "server.log"
Kill "server.log.old"
```

```output
server.log: 96 bytes
server.log.old: 288 bytes
```

### Debug messages in a finished program

A common way to use the levels: read the level from the program's settings (or its command
line), so that a user can switch on debug messages when you ask them to, without a new version
of the program.

*Listing 20.70* (`examples/book/ch20-libraries/listing-20-70.bas`)

<!-- run -->
```basic
Option Explicit
Dim lg As Logger
Set lg = CreateObject("Logger")
lg.Pattern = "{level}: {message}"
If InStr(LCase(Command), "debug") > 0 Then lg.Level = logDebug
lg.Debug "only with DEBUG on the command line"
lg.Info "to the console, because there is no FileName"
```

```output
INFO: to the console, because there is no FileName
```

### Errors

| Error | When |
|---|---|
| 75 | the log file can't be opened (for example, the drawer isn't there) |
| 61 | writing failed (the disk is full) |
| 380 | a negative `Level` or `MaxSize`, or a `Log` level outside 0-99 |

## XmlDocument: reading and writing XML

XML is a text format for structured data: news feeds (RSS), configuration files, the answers
of many web services, SVG pictures, office documents. An XML document is a tree of *elements*.
Each element has a name, can have *attributes* (`name="value"` pairs in its start tag), and
contains text and other elements:

```text
<rss version="2.0">
  <channel>
    <title>Amiga news</title>
    <item id="1"><title>New release</title><link>https://example.com/1</link></item>
  </channel>
</rss>
```

`XmlDocument` reads such a document into a tree of `XmlElement` objects. Your program can walk
the tree, find elements by name, read and change texts and attributes, add and remove elements,
and write the document back out as text or to a file.

<!-- fragment -->
```basic
Dim doc As XmlDocument, item As XmlElement
Set doc = CreateObject("XmlDocument")
doc.Load "PROGDIR:feed.rss"
For Each item In doc.FindAll("item")
    Print item.ChildText("title"); " - "; item.ChildText("link")
Next
```

### XmlDocument

| Member | What it does |
|---|---|
| `Load path` | reads a document from a file, replacing what was there. Error 31401 if it isn't well-formed XML. |
| `LoadXml text` | the same from a String (for example the body of a web page fetched with `Http`) |
| `Save path` | writes the document to a file, with an `<?xml ...?>` declaration first: the one that was read, or `<?xml version="1.0" encoding="ISO-8859-1"?>` |
| `Xml` | the whole document as text, declaration included. The default member. Assigning to it is the same as `LoadXml`. |
| `Root` | the top element, or `Nothing` for an empty document. Assigning an element (`Set doc.Root = e`) makes it the root. |
| `CreateRoot(name)` | empties the document and gives it a new root element with this name; returns the root |
| `CreateElement(name)` | a new element that isn't in the tree yet: put it there with `AppendChild` or `InsertBefore` |
| `Find(name)` | the first element with this name anywhere in the document, or `Nothing` |
| `FindAll(name)` | every element with this name anywhere in the document, in document order. `"*"` gives every element. |
| `Indent` | True (the default): `Xml`, `Save` and an element's `Xml` write one element per line, indented by two spaces. False: everything on one line. |

### XmlElement

| Member | What it does |
|---|---|
| `Name` | the tag name. You can assign a new one. |
| `Text` | all the text inside the element, the text of the elements inside it included. The default member. Assigning replaces everything inside the element with this text. |
| `Attribute(name [, default])` | an attribute's value, or the default (`""` if none) when it isn't there. `e.Attribute("id") = 7` sets it (and adds it if needed). |
| `HasAttribute(name)` | True if the element has the attribute |
| `RemoveAttribute(name)` | removes an attribute; True if it was there |
| `AttributeNames` | the attribute names, as an array of Strings in the order they appear |
| `Children` | the child elements (those directly inside this one), as a list |
| `ChildCount` | the number of child elements |
| `Child(name)` | the first child element with this name, or `Nothing` |
| `ChildText(name [, default])` | the text of that child, or the default (`""` if none) when there is no such child |
| `Find(name)` | the first element with this name inside this one, at any depth, or `Nothing` |
| `FindAll(name)` | every element with this name inside this one, at any depth (`"*"`: all of them) |
| `SelectNodes(path)` | the elements reached by a path of child names separated by `/`, starting below this element: `channel/item/title`. `*` in the path matches any name. |
| `Parent` | the element this one is in, or `Nothing` for the root (and for an element that isn't in the tree) |
| `Document` | the `XmlDocument` the element belongs to |
| `AddElement(name [, text])` | adds a new child element at the end, with this text in it; returns the new element |
| `AppendChild(element)` | moves an element to the end of this one: a new element from `CreateElement`, or one from elsewhere in the same document. Returns it. |
| `InsertBefore(element, child)` | the same, but places it before `child`, one of this element's children |
| `RemoveChild(element)` | takes one of this element's children out of the tree |
| `Remove` | takes this element out of the tree |
| `Xml` | the element with everything inside it, as XML text |
| `InnerXml` | what is inside the element, as XML text (without its own tags) |

`Children`, `FindAll` and `SelectNodes` return a list of elements. A list has `Count` and
`Item(i)`, counted from 0; `Item` is the default member, so `doc.FindAll("title")(0)` is the
first title. Go through a list with `For Each`. `Children` takes no argument, so write
`e.Children.Item(i)` (or `e.Children()(i)`), not `e.Children(i)`, which is error 438. A list is a snapshot: adding or removing elements
later doesn't change it.

Names are case-sensitive in XML: `Find("Title")` doesn't find `<title>`.

An element object stays usable after you remove it from the tree, and you can put it back with
`AppendChild`. An element can't be moved into another document.

### Example: reading a feed

The program reads a small RSS feed from a String (in a real program it comes from a file or
from the web) and lists the news items.

*Listing 20.71* (`examples/book/ch20-libraries/listing-20-71.bas`)

<!-- run -->
```basic
Option Explicit
Dim doc As XmlDocument, chan As XmlElement, item As XmlElement, t As Variant
Dim s As String

s = "<?xml version=""1.0"" encoding=""ISO-8859-1""?>" & vbLf & _
    "<rss version=""2.0"">" & vbLf & _
    "  <channel>" & vbLf & _
    "    <title>Amiga news</title>" & vbLf & _
    "    <item id=""101"" category=""software"">" & vbLf & _
    "      <title>Boing BASIC &amp; AmiForge released</title>" & vbLf & _
    "      <link>https://example.com/news/101</link>" & vbLf & _
    "    </item>" & vbLf & _
    "    <item id=""102"">" & vbLf & _
    "      <title>Meeting on Saturday</title>" & vbLf & _
    "      <link>https://example.com/news/102</link>" & vbLf & _
    "    </item>" & vbLf & _
    "  </channel>" & vbLf & _
    "</rss>"

Set doc = CreateObject("XmlDocument")
doc.LoadXml s
Print doc.Root.Name; " version "; doc.Root.Attribute("version")
Set chan = doc.Root.Child("channel")
Print "Feed: "; chan.ChildText("title"); ","; chan.ChildCount; "elements in the channel"
For Each item In doc.FindAll("item")
    Print item.Attribute("id"); " ("; item.Attribute("category", "general"); ") "; _
          item.ChildText("title")
    Print "    "; item.ChildText("link")
Next
For Each t In doc.Root.SelectNodes("channel/item/title")
    Print "title: "; t.Text
Next
Print doc.Find("guid") Is Nothing; " "; chan.Child("item").ChildText("guid", "(no guid)")
```

```output
rss version 2.0
Feed: Amiga news, 3 elements in the channel
101 (software) Boing BASIC & AmiForge released
    https://example.com/news/101
102 (general) Meeting on Saturday
    https://example.com/news/102
title: Boing BASIC & AmiForge released
title: Meeting on Saturday
True (no guid)
```

`&amp;` in the document became `&` in the text: the reader turns XML's escapes into the
characters they stand for, and the writer turns them back.

`SelectNodes("channel/item/title")` starts *below* the root, so the path doesn't name `rss`
itself. `FindAll("title")` would also have found the channel's own title.

### Example: building and changing a document

The program builds a high-score table, changes it, and prints it, indented and on one line.

*Listing 20.72* (`examples/book/ch20-libraries/listing-20-72.bas`)

<!-- run -->
```basic
Option Explicit
Dim doc As XmlDocument, root As XmlElement, e As XmlElement
Dim names As Variant, points As Variant, i As Long

names = Array("Ann", "Bob", "Cy")
points = Array(5200, 4100, 900)
Set doc = CreateObject("XmlDocument")
Set root = doc.CreateRoot("highscores")
root.Attribute("game") = "Boing & Bounce"
For i = 0 To 2
    Set e = root.AddElement("score", CStr(points(i)))
    e.Attribute("player") = names(i)
Next
Print doc.Xml

' a new best score goes first
Set e = doc.CreateElement("score")
e.Text = "6000"
e.Attribute("player") = "Dee"
root.InsertBefore e, root.Child("score")
' the last one drops off the table
root.Children.Item(root.ChildCount - 1).Remove
' rename an attribute: read it, add the new one, remove the old one
For Each e In root.Children
    e.Attribute("name") = e.Attribute("player")
    e.RemoveAttribute "player"
Next
doc.Indent = False
Print root.Xml
Print root.InnerXml
```

```output
<?xml version="1.0" encoding="ISO-8859-1"?>
<highscores game="Boing &amp; Bounce">
  <score player="Ann">5200</score>
  <score player="Bob">4100</score>
  <score player="Cy">900</score>
</highscores>

<highscores game="Boing &amp; Bounce"><score name="Dee">6000</score><score name="Ann">5200</score><score name="Bob">4100</score></highscores>
<score name="Dee">6000</score><score name="Ann">5200</score><score name="Bob">4100</score>
```

To keep the table between runs, `doc.Save "PROGDIR:scores.xml"` writes it and
`doc.Load "PROGDIR:scores.xml"` reads it back.

### What is supported

The reader understands:

- elements and attributes (values in `"` or `'`), and empty elements (`<empty/>`);
- text and `<![CDATA[...]]>` sections, which become ordinary text;
- the entities `&lt;` `&gt;` `&amp;` `&quot;` `&apos;` and character references such as
  `&#233;` and `&#xE9;`.

Comments, processing instructions and `<!DOCTYPE ...>` are read past and not kept, so `Save`
doesn't write them back. Text that is only white space between elements is dropped, so an
indented file doesn't give you empty texts. When writing, `<`, `>` and `&` are escaped in texts,
and also `"` and line breaks in attribute values.

**Characters.** A Boing BASIC String is a sequence of bytes. A character reference below 256
becomes that byte (Latin-1, the Amiga's character set); higher ones are stored as UTF-8. The
text of a UTF-8 document stays UTF-8: convert it yourself if you need Latin-1.

There are no namespaces (a name like `dc:title` is just a name with a colon in it), no DTD
validation, and no XPath beyond the simple paths of `SelectNodes`.

### Errors

| Error | When |
|---|---|
| 31401 | the text isn't well-formed XML. `Err.Description` says what is wrong and on which line, for example `bad XML: </b> doesn't close <a> (line 3)`. |
| 53 | `Load`: the file isn't there |
| 75, 61 | `Save`: the file can't be created, or writing failed |
| 5 | an invalid element or attribute name, an element put inside itself, an element from another document, or `InsertBefore` with an element that isn't a child |
| 9 | a list index out of range |

*Listing 20.73* (`examples/book/ch20-libraries/listing-20-73.bas`)

<!-- run -->
```basic
Option Explicit
Dim doc As XmlDocument, bad As Variant, i As Long
Set doc = CreateObject("XmlDocument")
bad = Array("<a><b></a>", "<a b=1/>", "<a/><b/>", "")
On Error Resume Next
For i = 0 To UBound(bad)
    doc.LoadXml bad(i)
    Print Err.Number; Err.Description
    Err.Clear
Next
doc.LoadXml "<a/>"
doc.Root.AddElement "two words"
Print Err.Number; Err.Description
```

```output
 31401 bad XML: </a> doesn't close <b> (line 1)
 31401 bad XML: an attribute value must be in quotes (line 1)
 31401 bad XML: more than one root element (line 1)
 31401 bad XML: no root element (line 1)
 5 not a valid element name
```

## Compression and Zip archives

Boing BASIC can compress data and read and write ZIP archives, the same way on AmigaOS 4 and
on the host. Two built-in functions compress and decompress a String: use them to make saved
games or caches smaller, to write and read `.gz` files, or to unpack compressed data from the
web. The `Zip` class reads and writes ZIP archives, the most common archive format outside the
Amiga (and read by the Amiga's own archivers too): unpack a download, or pack a backup of a
program's files.

### Compress and Decompress

| Function | What it returns |
|---|---|
| `Compress(data [, format [, level]])` | `data`, compressed |
| `Decompress(data [, format])` | the original data |

`data` is any String, text or binary. The formats are three ways of wrapping the same
compression method (deflate):

| Constant | Format |
|---|---|
| `zipGzip` | the contents of a `.gz` file (the gzip program's format). The default for `Compress`. |
| `zipZlib` | zlib, a smaller header, used inside PNG pictures and by many web services |
| `zipDeflate` | raw deflate data, with no header at all |
| `zipAuto` | (only for `Decompress`, and its default) gzip or zlib, recognised by their headers |

Raw deflate data has no header to recognise, so decompress it with `Decompress(data, zipDeflate)`.

`level` is how hard `Compress` works: 0 only stores the data (the result is a little larger
than the original), 1 is the fastest, 9 gives the smallest result, and the default is 6. All
levels decompress the same way. (Level 9 is not always smaller than 6: on some data it gains
nothing, or comes out a byte larger.)

Both gzip and zlib data carry a checksum of the original data, and `Decompress` checks it:
damaged data gives error 31501 rather than wrong text.

*Listing 20.74* (`examples/book/ch20-libraries/listing-20-74.bas`)

<!-- run -->
```basic
Option Explicit
Dim s As String, packed As String, i As Long

For i = 1 To 200
    s = s & "Line " & i & " of a text that repeats itself a lot." & vbLf
Next
packed = Compress(s)
Print "original:"; Len(s); "bytes"
Print "gzip, a tenth or less: "; Len(packed) <= Len(s) \ 10
Print "zlib, level 9, recognised: "; Decompress(Compress(s, zipZlib, 9)) = s
Print "stored (level 0):"; Len(Compress(s, zipGzip, 0)); "bytes"
Print "round trip ok: "; Decompress(packed) = s
Print "raw deflate ok: "; Decompress(Compress(s, zipDeflate), zipDeflate) = s
```

```output
original: 9092 bytes
gzip, a tenth or less: True
zlib, level 9, recognised: True
stored (level 0): 9115 bytes
round trip ok: True
raw deflate ok: True
```

Text that repeats itself, like this one, gets much smaller; data that is already compressed
(JPEG pictures, LhA and ZIP archives, MP3 files) doesn't get smaller at all. The program
compares sizes instead of printing them, because the exact compressed size can differ by a few
bytes between versions of the compression library (the Amiga's and the host's, for example);
the stored size (level 0: the data plus 23 bytes of gzip header and checksum) is always the same.

`Compress` with the default format gives exactly the contents of a `.gz` file. Write it with
`Put` in Binary mode, and read one back the same way:

<!-- fragment -->
```basic
packed = Compress(report)
Open "RAM:report.txt.gz" For Binary As #1
Put #1, 1, packed
Close #1
```

A checksum of the kind ZIP and gzip use, CRC-32, is the hashing function `Crc32(data)`, not
part of the compression functions.

### The Zip class: reading an archive

A ZIP archive holds *entries*: files, and folders that contain them. Each entry has a name with
`/` between folder names (`docs/readme.txt`); a folder entry's name ends in `/`.

| Member | What it does |
|---|---|
| `Open path` | opens an archive and reads its list of entries. Error 53 if the file isn't there, 31501 if it isn't a ZIP file. |
| `Count` | the number of entries |
| `Name(i)` | the name of entry `i`, counted from 0 |
| `Size(i)` | the size of the entry's data, in bytes |
| `CompressedSize(i)` | the size it takes in the archive |
| `IsFolder(i)` | True for a folder entry |
| `FileDate(i)` | the date and time stored with the entry, as a Date |
| `IndexOf(name)` | the index of the entry with this name (in any case), or -1 if there is none |
| `Read(entry)` | the data of an entry, as a String. `entry` is an index or a name. |
| `Extract entry, path` | writes one entry to a file, creating the folders in `path` that aren't there yet |
| `ExtractAll(folder)` | writes every entry into `folder`, with their folders; returns how many it wrote |
| `Path` | the file name of the open archive (read-only) |
| `Close` | closes the archive |

`Size`, `CompressedSize`, `IsFolder` and `FileDate` also take an entry's name instead of its
index. Every entry's size and checksum are checked when it is read or extracted, so a damaged
entry gives error 31501 ("... is damaged") instead of bad data.

`ExtractAll` skips entries with absolute names (`/etc/x`, `DH0:x`) or with `..` in them: an
archive from somewhere else can't write files outside the folder you chose.

<!-- fragment -->
```basic
Dim z As Zip
Set z = CreateObject("Zip")
z.Open "RAM:download.zip"
Print z.ExtractAll("RAM:download/"); "files unpacked"
z.Close
```

### The Zip class: writing an archive

| Member | What it does |
|---|---|
| `Create path` | starts a new archive, replacing a file of that name |
| `AddText name, data` | adds an entry with this name, holding a String |
| `AddFile path [, name]` | adds a file. `name` is its name in the archive; the default is the file's own name (without its drawer). |
| `AddFolder path [, name]` | adds a folder with everything in it. `name` is the folder's name in the archive; without it the folder's contents go to the top of the archive. |
| `Level` | the compression level for the next entries: 0 (store) to 9, default 6. An entry that wouldn't get smaller is stored. |
| `Count` | the number of entries added so far |
| `Close` | writes the archive's directory and closes the file |

**An archive is only complete after `Close`**, which writes the list of entries at the end of
the file. `Close` also happens when the `Zip` object goes away (at the end of the program, or
when you `Set z = Nothing`), but call it yourself, so that you know the archive is finished.

The archives are standard ZIP files that `unzip`, Windows, macOS and the AmigaOS archivers read.

*Listing 20.75* (`examples/book/ch20-libraries/listing-20-75.bas`)

<!-- run -->
```basic
Option Explicit
Dim z As Zip, i As Long, notes As String

notes = "Shopping list" & vbLf & String(20, "-") & vbLf
For i = 1 To 30
    notes = notes & "item " & i & ": something to buy" & vbLf
Next

Set z = CreateObject("Zip")
z.Create "texts.zip"
z.AddText "readme.txt", "Made with Boing BASIC" & vbLf
z.AddText "notes/shopping.txt", notes
z.Close

z.Open "texts.zip"
Print z.Path; " has"; z.Count; "entries"
For i = 0 To z.Count - 1
    Print "  "; z.Name(i); z.Size(i); "bytes, smaller in the archive: "; z.CompressedSize(i) < z.Size(i)
Next
Print z.Read("readme.txt");
Print "notes ok: "; z.Read(z.IndexOf("NOTES/SHOPPING.TXT")) = notes
z.Close
Kill "texts.zip"
```

```output
texts.zip has 2 entries
  readme.txt 22 bytes, smaller in the archive: False
  notes/shopping.txt 806 bytes, smaller in the archive: True
Made with Boing BASIC
notes ok: True
```

The short `readme.txt` wouldn't get smaller, so it was stored as it is. The folder `notes/`
needs no entry of its own: `ExtractAll` creates it from the entry's name.

A backup of a program's saved games, with a note in it:

<!-- fragment -->
```basic
Dim z As Zip
Set z = CreateObject("Zip")
z.Create "RAM:backup.zip"
z.AddFolder "PROGDIR:saves", "saves"
z.AddText "info.txt", "Backup of " & Now
z.Close
```

### z.library on AmigaOS

On AmigaOS 4 the compression itself is done by `z.library` (zlib as a shared library, version
53 or newer, part of AmigaOS 4.1 since Update 1). It is opened the first time a program
compresses or decompresses something, so a program that never does doesn't need it. If it is
missing, you get error 31502 ("compression needs z.library"). On the host the system's zlib is
used in the same way. The ZIP format itself (the directory, the headers, the checks) is
Boing BASIC's own code.

### Not supported

ZIP64 (archives or entries over 4 GB), encrypted (password-protected) entries, compression
methods other than store and deflate (for example bzip2 or LZMA entries), archives split over
several disks, file comments, and the Amiga's protection bits and file notes (they aren't
stored or restored). LhA and LZX archives are not ZIP files: `Open` gives error 31501.

### Errors

| Error | When |
|---|---|
| 31501 | not a ZIP file, a damaged archive or entry, or damaged compressed data in `Decompress` |
| 31502 | no compression library (`z.library` missing on AmigaOS) |
| 53 | the archive or a file to add isn't there, or no entry has that name |
| 75, 61 | a file can't be created, or writing failed |
| 5 | adding to an archive opened with `Open`, reading one made with `Create`, a bad entry name (empty, absolute or with `..`), or a bad format number |
| 380 | a `Level` outside 0-9 |
| 9 | an entry index out of range |

*Listing 20.76* (`examples/book/ch20-libraries/listing-20-76.bas`)

<!-- run -->
```basic
Option Explicit
Dim z As Zip, s As String
Set z = CreateObject("Zip")
On Error Resume Next
z.Open "no-such.zip"
Print "missing:"; Err.Number: Err.Clear
s = Decompress("this was never compressed")
Print "damaged:"; Err.Number: Err.Clear
z.Create "bad.zip"
z.AddText "../outside.txt", "x"
Print "bad name:"; Err.Number; Err.Description: Err.Clear
z.Level = 10
Print "level:"; Err.Number: Err.Clear
z.Close
Kill "bad.zip"
```

```output
missing: 53 
damaged: 31501 
bad name: 5 a bad name for an entry (empty, absolute or with ..)
level: 380 
```

## SQL databases: SQLite

`SQLite` gives your program a complete SQL database in a single file: tables, indexes,
queries that search, sort, count and combine data, and transactions that keep the data whole
when something goes wrong. Use it for anything bigger than a settings file: an address book, a
record collection, a game's high scores and save slots, a log you want to search.

SQL is the language you talk to the database in. This section shows the SQL it uses as it goes
(`CREATE TABLE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`); SQLite understands standard SQL, and
its own documentation (sqlite.org) describes all of it.

### Asking for SQLite: Extension=sqlite

Unlike the other libraries in this chapter, SQLite isn't part of every program. It is a
**standard extension**: a program that uses it says so in its project file with one line,

```ini
Extension=sqlite
```

and the classes `SQLite`, `SqlRecordset` and `SqlStatement` are then there. A single `.bas` file
can't name an extension, so a program that uses SQLite is always a project (a `.bbp` file, see
[Projects](02-shell.md#projects)). Without the line, the program doesn't compile:

<!-- error: type 'SQLite' is not defined -->
```basic
Option Explicit
Dim db As SQLite
Set db = CreateObject("SQLite")
```

How the extension gets into the program depends on how you run it:

- **`boing run` and AmiForge's Run.** The interpreter in the Boing BASIC kit has SQLite built
  in, so `boing run Records.bbp` (and Run in AmiForge, which uses it) just works.
- **An interpreter without it.** A `boing` you built yourself without SQLite stops with "this
  program needs the extension 'sqlite', which is not linked into this interpreter". Make an
  interpreter that has it with `boing vm`, and run the program with that:

  ```sh
  boing vm --project Records.bbp -o myboing
  myboing run Records.bbp
  ```

  `myboing` looks for the extension's description (`ext/sqlite/sqlite.bbx`) in the `ext`
  drawer beside itself, as `boing` does, so keep it in the same drawer as `boing`, or set the
  environment variable `BOING_EXT` to the `ext` drawer of your Boing BASIC installation.
- **Native programs.** `boing build Records.bbp` (and AmiForge's Build) reads the `Extension=`
  line and links SQLite into the program. On AmigaOS 4 the SQLite engine from the AmigaOS SDK
  is built into the executable, so nothing needs to be installed on the Amiga that runs it; it
  adds about 900 KB, which is why only the programs that ask for it get it. On macOS and Linux
  the system's SQLite library is used (on Linux, install its development package to build).

[Standard extensions](21-extending.md#standard-extensions) in chapter 21 says more about how
they are found and built in.

Every example in this section is a small project in `examples/book/ch20-libraries/`. Here is
the first, `albums`: its project file and its program.

```ini
# Albums: a first SQLite database, in memory (manual chapter 20)
Name=Albums
Startup=Sub Main
Module=albums.bas
Extension=sqlite
```

*Listing 20.77* (`examples/book/ch20-libraries/albums/albums.bbp`)

<!-- project: examples/book/ch20-libraries/albums/albums.bbp -->
```basic
' albums.bas - a table, three rows, a query (Extension=sqlite in albums.bbp)
Option Explicit

Sub Main()
    Dim db As SQLite, rs As SqlRecordset

    Set db = CreateObject("SQLite")
    db.Open ":memory:"
    db.Execute "CREATE TABLE album (id INTEGER PRIMARY KEY, artist TEXT, title TEXT, year INTEGER)"
    db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Kraftwerk", "Computer World", 1981
    db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Jean-Michel Jarre", "Oxygene", 1976
    db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Daft Punk", "Discovery", 2001
    Set rs = db.Query("SELECT artist, title, year FROM album WHERE year < ? ORDER BY year", 1990)
    Do Until rs.AtEnd
        Print rs("year"); rs("artist"); " - "; rs("title")
        rs.MoveNext
    Loop
    rs.Close
    Print db.QueryValue("SELECT COUNT(*) FROM album"); "albums"
    db.Close
End Sub
```

```output
 1976 Jean-Michel Jarre - Oxygene
 1981 Kraftwerk - Computer World
 3 albums
```

`":memory:"` is a database that lives in memory and goes away when it is closed: handy for
trying things out, and for most examples here. A real program gives a file name, and the data
is there again the next time it runs. `records` writes a row, closes the database, and opens
it again (read-only this time) to find the row still there:

*Listing 20.78* (`examples/book/ch20-libraries/records/records.bbp`)

<!-- project: examples/book/ch20-libraries/records/records.bbp -->
```basic
' records.bas - a database file: the rows are still there when it is opened again
Option Explicit
Dim db As SQLite

Set db = CreateObject("SQLite")
db.Open "records.db"
db.Execute "CREATE TABLE IF NOT EXISTS album (id INTEGER PRIMARY KEY, artist TEXT, title TEXT, year INTEGER)"
db.Execute "INSERT INTO album (artist, title, year) VALUES (?, ?, ?)", "Kraftwerk", "Computer World", 1981
Print "open:"; db.IsOpen; " file: "; db.Path
db.Close
Print "open:"; db.IsOpen

' the next run of a program, or another program
db.Open "records.db", True              ' True: read-only
Print db.QueryValue("SELECT COUNT(*) FROM album"); "album: "; db.QueryValue("SELECT title FROM album")
db.Close
Kill "records.db"                       ' only for this example: a real program keeps its file
```

```output
open:True file: records.db
open:False
 1 album: Computer World
```

SQLite takes the file name exactly as you give it. A name without a drawer, as here, is in the
current drawer; a program that keeps its database beside itself puts `App.Path` in front of the
name (the address book below shows how).

### The SQLite object (the database)

| Member | What it does |
|---|---|
| `Open path [, readOnly]` | opens a database file, creating it if it isn't there (unless `readOnly` is True). `":memory:"` opens a new, empty database in memory. Opening while a database is open closes that one first. |
| `Close` | closes the database |
| `Execute(sql, values...)` | runs a statement (`CREATE`, `INSERT`, `UPDATE`, `DELETE`, ...) and returns the number of rows it changed. Without values, the text may hold several statements separated by `;`. |
| `Query(sql, values...)` | runs a `SELECT` and returns an `SqlRecordset` on its first row |
| `QueryValue(sql, values...)` | the first column of the first row, or Empty if there is no row: `n = db.QueryValue("SELECT COUNT(*) FROM album")` |
| `QueryAll(sql, values...)` | every row, as a two-dimensional array `a(row, column)`, both counted from 0; Empty if there are no rows |
| `Prepare(sql)` | an `SqlStatement`: a statement to run many times with different values |
| `BeginTransaction` | starts a transaction (see below) |
| `Commit` | ends it, keeping the changes |
| `Rollback` | ends it, undoing every change since `BeginTransaction` |
| `InTransaction` | True between `BeginTransaction` and `Commit` or `Rollback` |
| `LastInsertId` | the id (the `INTEGER PRIMARY KEY`) of the last row inserted |
| `Changes` | the number of rows changed by the last statement |
| `IsOpen` | True while a database is open |
| `Path` | the file name given to `Open` |
| `ErrorCode` | SQLite's own number for the last error, for example 2067 for a value that must be unique and isn't |
| `Timeout` | how long, in milliseconds, to wait for a database that another program is writing to; default 5000 |
| `Version` | the version of SQLite, such as `3.34.0` (the one in AmigaOS programs) |
| `Available` | True when SQLite can be used: always, in a program that has the extension |

### Parameters: always use `?`

The values after the SQL text fill the `?` marks in it, in order:

<!-- fragment -->
```basic
db.Execute "INSERT INTO contact (name, phone) VALUES (?, ?)", nameField.Text, phoneField.Text
Set rs = db.Query("SELECT * FROM contact WHERE name LIKE ?", search & "%")
```

You could also paste the values into the SQL text yourself, but don't. A text value has to be
written in quotes in SQL, so a name with a quote in it, such as `O'Brien`, breaks the statement:

```text
INSERT INTO contact (name) VALUES ('O'Brien')          -> syntax error
```

Worse, a value that someone else typed (in a form, a file or a web page) can *change* the
statement: a "name" like `x'); DELETE FROM contact; --` would delete every contact. This is
called SQL injection, and it is one of the most common security holes in programs. With `?`
the value is never read as SQL: whatever it contains, it is stored as it is. Parameters also
keep numbers and dates in their types, and save you converting them to text.

*Listing 20.79* (`examples/book/ch20-libraries/injection/injection.bbp`)

<!-- project: examples/book/ch20-libraries/injection/injection.bbp -->
```basic
' injection.bas - a value full of quotes and SQL is stored as it is
Option Explicit
Dim db As SQLite, nasty As String

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE contact (id INTEGER PRIMARY KEY, name TEXT)"
nasty = "O'Brien'); DELETE FROM contact; --"
db.Execute "INSERT INTO contact (name) VALUES (?)", "Ann"
db.Execute "INSERT INTO contact (name) VALUES (?)", nasty
db.Execute "INSERT INTO contact (name) VALUES (?)", Array("Bob")
Print db.QueryValue("SELECT COUNT(*) FROM contact"); "contacts"
Print db.QueryValue("SELECT name FROM contact WHERE id = ?", 2)
Print db.QueryValue("SELECT id FROM contact WHERE name LIKE ?", "b%")
```

```output
 3 contacts
O'Brien'); DELETE FROM contact; --
 3 
```

The number of values must match the number of `?` marks (error 450 if not). You can also pass
the values as one array, as the third `INSERT` does: `db.Execute sql, Array(a, b, c)`.
Parameters can't be used in a text with several statements (error 450).

Parameters stand for *values* only. Table and column names can't be parameters: if a program
must choose a column at run time, pick its name from a fixed list in your code, never from
what a user typed.

### SqlRecordset: the rows of a query

`Query` returns an `SqlRecordset`, which stands on one row of the result at a time.

| Member | What it does |
|---|---|
| `AtEnd` | True when there are no (more) rows. `EOF` is the same. |
| `MoveNext` | moves to the next row (error 31601 after the last one: check `AtEnd`) |
| `Field(column)` | a value of the current row. `column` is a column name (in any case) or a position counted from 0. The default member: `rs("title")`, `rs(0)`. |
| `Fields` | the current row, as an array of Variants |
| `FieldCount` | the number of columns |
| `FieldName(i)` | the name of column `i` |
| `RowNumber` | 1 on the first row, 2 on the second, ...; 0 after the end |
| `Close` | finishes the query (it also happens when the recordset goes away) |

The usual loop is `Do Until rs.AtEnd ... rs.MoveNext ... Loop`. `For Each` is shorter: it gives
each row as an array. For a small result, `QueryAll` gives all of it at once, and `QueryValue`
a single value. `scores` reads one table all four ways:

*Listing 20.80* (`examples/book/ch20-libraries/scores/scores.bbp`)

<!-- project: examples/book/ch20-libraries/scores/scores.bbp -->
```basic
' scores.bas - a recordset loop, For Each, QueryAll and QueryValue
Option Explicit
Dim db As SQLite, rs As SqlRecordset, row As Variant, a As Variant, i As Long

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE score (player TEXT, points INTEGER, level INTEGER);" & _
           "INSERT INTO score VALUES ('Ann', 5200, 7), ('Bob', 4100, 5), ('Cy', 900, 2), ('Ann', 3000, 4)"

Set rs = db.Query("SELECT player, SUM(points) AS total FROM score GROUP BY player ORDER BY total DESC")
Print rs.FieldCount; "columns: "; rs.FieldName(0); ", "; rs.FieldName(1)
Do Until rs.AtEnd
    Print rs.RowNumber; ". "; rs("player"); rs("total")
    rs.MoveNext
Loop
rs.Close

For Each row In db.Query("SELECT player, level FROM score WHERE level > ?", 4)
    Print row(0); " reached level"; row(1)
Next

a = db.QueryAll("SELECT player, points FROM score ORDER BY points")
For i = 0 To UBound(a, 1)
    Print a(i, 0); "="; a(i, 1); " ";
Next
Print
Print "best: "; db.QueryValue("SELECT MAX(points) FROM score")
Print "nobody: "; IsEmpty(db.QueryValue("SELECT player FROM score WHERE points > 99999"))
```

```output
 2 columns: player, total
 1 . Ann 8200 
 2 . Bob 4100 
 3 . Cy 900 
Ann reached level 7 
Bob reached level 5 
Cy= 900  Ann= 3000  Bob= 4100  Ann= 5200  
best:  5200 
nobody: True
```

A column made from an expression, such as `SUM(points)`, is named after it; `AS total` gives it
a shorter name to use in `rs("total")`.

### Types

Each value in SQLite has one of five types. They map onto Boing BASIC's types like this:

| SQLite | Read as | Written from |
|---|---|---|
| INTEGER | Long (Double beyond +-2147483647) | Byte, Integer, Long, Boolean (True is stored as 1, False as 0), Currency without a fraction |
| REAL | Double | Single, Double, Currency with a fraction |
| TEXT | String | String; a Date is stored as text `yyyy-mm-dd hh:nn:ss`, which SQLite's date functions understand |
| BLOB | String (its bytes) | (a String is stored as TEXT, but every byte is kept, zero bytes too) |
| NULL | Null | Null or Empty |

`sqltypes` stores one value of each kind and asks SQLite (with its `typeof` function) how it
was stored:

*Listing 20.81* (`examples/book/ch20-libraries/sqltypes/sqltypes.bbp`)

<!-- project: examples/book/ch20-libraries/sqltypes/sqltypes.bbp -->
```basic
' sqltypes.bas - each kind of value in, and what comes back out
Option Explicit
Dim db As SQLite, rs As SqlRecordset

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE t (what TEXT, v)"
db.Execute "INSERT INTO t VALUES (?, ?)", "Long", 42
db.Execute "INSERT INTO t VALUES ('big integer', 3000000000)"
db.Execute "INSERT INTO t VALUES (?, ?)", "Double", 2.5
db.Execute "INSERT INTO t VALUES (?, ?)", "Currency", CCur(19.99)
db.Execute "INSERT INTO t VALUES (?, ?)", "whole Currency", CCur(20)
db.Execute "INSERT INTO t VALUES (?, ?)", "Boolean", True
db.Execute "INSERT INTO t VALUES (?, ?)", "Date", DateSerial(2026, 11, 10) + TimeSerial(14, 30, 0)
db.Execute "INSERT INTO t VALUES (?, ?)", "bytes", "A" & Chr(0) & "B"
db.Execute "INSERT INTO t VALUES (?, ?)", "Null", Null
db.Execute "INSERT INTO t VALUES (?, ?)", "Empty", Empty
db.Execute "INSERT INTO t (what) VALUES ('no value')"

Set rs = db.Query("SELECT what, v, typeof(v) FROM t")
Do Until rs.AtEnd
    Print rs(0); ": stored as "; rs(2); ", read as "; TypeName(rs(1))
    rs.MoveNext
Loop
Print Len(db.QueryValue("SELECT v FROM t WHERE what = 'bytes'")); "bytes"
Print db.QueryValue("SELECT v FROM t WHERE what = 'Date'")
Print Year(CDate(db.QueryValue("SELECT v FROM t WHERE what = 'Date'")))
Print db.QueryValue("SELECT date(v, '+1 month') FROM t WHERE what = 'Date'")
Print "["; db.QueryValue("SELECT IFNULL(v, '') FROM t WHERE what = 'no value'"); "]"
```

```output
Long: stored as integer, read as Long
big integer: stored as integer, read as Double
Double: stored as real, read as Double
Currency: stored as real, read as Double
whole Currency: stored as integer, read as Long
Boolean: stored as integer, read as Long
Date: stored as text, read as String
bytes: stored as text, read as String
Null: stored as null, read as Null
Empty: stored as null, read as Null
no value: stored as null, read as Null
 3 bytes
2026-11-10 14:30:00
 2026 
2026-12-10
[]
```

Columns that hold nothing are Null when you read them: test with `IsNull`, or write
`SELECT IFNULL(phone, '') ...` to get an empty text instead. Dates come back as text; turn
them into a Date with `CDate`, or let SQLite work with them (`date(v, '+1 month')`). A value
can't be an object or an array (error 13).

### SqlStatement: prepared statements

`Prepare` reads and checks a statement once; you then run it as often as you like with new
values. In a loop this is much faster than calling `db.Execute` with the same SQL each time.

| Member | What it does |
|---|---|
| `Execute(values...)` | runs the statement with these values; returns the number of rows changed |
| `Query(values...)` | runs a `SELECT` with these values and returns an `SqlRecordset`. Close the recordset before you use the statement again. |
| `ParameterCount` | the number of `?` marks in the statement |
| `Close` | frees the statement |

### Transactions

Normally each statement is saved to the disk on its own. Between `BeginTransaction` and
`Commit`, the changes are kept together: they are saved all at once at `Commit`, and
`Rollback` undoes all of them. This has two uses:

- **Speed.** Saving each statement to the disk takes time, on the Amiga especially. A thousand
  inserts in one transaction are many times faster than a thousand on their own.
- **All or nothing.** Moving money from one account to another is two `UPDATE`s; if the
  program fails between them, `Rollback` (or a crash: SQLite then rolls back by itself) leaves
  the data as it was before.

`readings` uses one prepared statement for a thousand inserts in one transaction, then
deletes a third of them and changes its mind:

*Listing 20.82* (`examples/book/ch20-libraries/readings/readings.bbp`)

<!-- project: examples/book/ch20-libraries/readings/readings.bbp -->
```basic
' readings.bas - a thousand inserts in one transaction, and a rollback
Option Explicit
Dim db As SQLite, ins As SqlStatement, i As Long

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE reading (id INTEGER PRIMARY KEY, sensor TEXT, value REAL)"

Set ins = db.Prepare("INSERT INTO reading (sensor, value) VALUES (?, ?)")
Print "parameters:"; ins.ParameterCount
db.BeginTransaction
For i = 1 To 1000
    ins.Execute "temp" & (i Mod 3), i / 10
Next
db.Commit
ins.Close
Print "rows:"; db.QueryValue("SELECT COUNT(*) FROM reading"); " last id:"; db.LastInsertId

db.BeginTransaction
Print "deleted:"; db.Execute("DELETE FROM reading WHERE sensor = ?", "temp0"); db.InTransaction
db.Rollback
Print "after rollback:"; db.QueryValue("SELECT COUNT(*) FROM reading"); db.InTransaction
Print "average:"; db.QueryValue("SELECT ROUND(AVG(value), 2) FROM reading WHERE sensor = 'temp1'")
```

```output
parameters: 2 
rows: 1000  last id: 1000 
deleted: 333 True
after rollback: 1000 False
average: 50.05 
```

When an error can happen inside a transaction, roll it back in your error handler. In
`transfer`, the table won't let a balance go below zero (`CHECK (balance >= 0)`). The second
transfer adds 500 to Ann's account, then fails taking it from Bob's; `Rollback` takes the 500
back off Ann's account, so no money appears from nowhere:

*Listing 20.83* (`examples/book/ch20-libraries/transfer/transfer.bbp`)

<!-- project: examples/book/ch20-libraries/transfer/transfer.bbp -->
```basic
' transfer.bas - two UPDATEs that happen together or not at all
Option Explicit
Dim db As SQLite

Sub Transfer(ByVal amount As Long, ByVal fromId As Long, ByVal toId As Long)
    On Error GoTo Failed
    db.BeginTransaction
    db.Execute "UPDATE account SET balance = balance + ? WHERE id = ?", amount, toId
    db.Execute "UPDATE account SET balance = balance - ? WHERE id = ?", amount, fromId
    db.Commit
    Print "moved"; amount
    Exit Sub
Failed:
    If db.InTransaction Then db.Rollback
    Print "the transfer of"; amount; "failed: "; Err.Description
End Sub

Sub Balances()
    Dim row As Variant
    For Each row In db.Query("SELECT name, balance FROM account ORDER BY id")
        Print "  "; row(0); row(1)
    Next
End Sub

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE account (id INTEGER PRIMARY KEY, name TEXT, balance INTEGER CHECK (balance >= 0));" & _
           "INSERT INTO account (name, balance) VALUES ('Ann', 100), ('Bob', 20)"
Transfer 30, 1, 2
Transfer 500, 2, 1
Balances
```

```output
moved 30 
the transfer of 500 failed: CHECK constraint failed: balance >= 0
  Ann 70 
  Bob 50 
```

### Example: an address book

`examples/book/ch20-libraries/addressbook` is a small form program: a list of contacts, fields
to edit the selected one, and buttons to add, save and delete. The contacts are kept in an
SQLite file next to the program. Each row of the list keeps its contact's id in `ItemData`, so
the program always knows which row of the table belongs to which row of the list. Its project
file names the form and asks for SQLite:

```ini
# Boing BASIC project: an address book kept in an SQLite database (manual chapter 20)
Name=AddressBook
Startup=Form contacts
Form=contacts.afg
Extension=sqlite
```

```text
# contacts.afg
window name=contacts title="Address Book" width=560 height=320 resizable=1
hlayout id=root splitter=1
  listbrowser id=people columns="Name|Phone" widths="60|40" weight=45
  vlayout weight=55
    string id=nameField label="_Name" maxchars=80
    string id=phoneField label="_Phone" maxchars=40
    string id=emailField label="_E-mail" maxchars=80
    string id=notesField label="N_otes" maxchars=200
    hlayout weight=0
      button id=addButton text="_Add"
      button id=saveButton text="_Save"
      button id=deleteButton text="_Delete"
    space
    label id=status text=" "
```

Opening the database and creating the table the first time:

*Listing 20.84* (`examples/book/ch20-libraries/addressbook/addressbook.bbp`)

<!-- project: examples/book/ch20-libraries/addressbook/addressbook.bbp -->
```basic
Private Function DataFile(ByVal name As String) As String
    Dim p As String
    p = App.Path
    If p = "" Or Right(p, 1) = ":" Or Right(p, 1) = "/" Then DataFile = p & name Else DataFile = p & "/" & name
End Function

Private Sub Form_Load()
    Set db = CreateObject("SQLite")
    db.Open DataFile("AddressBook.db")
    db.Execute "CREATE TABLE IF NOT EXISTS contact (" & _
               "id INTEGER PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT, notes TEXT)"
    If db.QueryValue("SELECT COUNT(*) FROM contact") = 0 Then AddSamples
    LoadList 0
End Sub
```

`DataFile` puts the program's drawer, `App.Path`, in front of the file name, with a `/` only
when the drawer isn't a volume such as `DH1:`, so the database is found wherever the program
is started from. `CREATE TABLE IF NOT EXISTS` makes the table the first time and does nothing
after that.

Filling the list from the table, and showing the selected contact:

*Listing 20.85* (`examples/book/ch20-libraries/addressbook/addressbook.bbp`)

<!-- project: examples/book/ch20-libraries/addressbook/addressbook.bbp -->
```basic
Private Sub LoadList(ByVal selectId As Long)
    Dim rs As SqlRecordset, n As Long
    people.Clear
    Set rs = db.Query("SELECT id, name, IFNULL(phone, '') FROM contact ORDER BY name COLLATE NOCASE")
    Do Until rs.AtEnd
        people.AddItem rs(1) & vbTab & rs(2)
        people.ItemData(people.ListCount - 1) = rs(0)
        If rs(0) = selectId Then n = people.ListCount - 1
        rs.MoveNext
    Loop
    rs.Close
    If people.ListCount > 0 Then people.ListIndex = n Else ShowContact 0
End Sub

Private Sub people_Click()
    If people.ListIndex >= 0 Then ShowContact people.ItemData(people.ListIndex)
End Sub
```

Saving: a new contact is an `INSERT`, a changed one an `UPDATE`, always with `?` parameters, so
that whatever the user typed is stored as it is:

*Listing 20.86* (`examples/book/ch20-libraries/addressbook/addressbook.bbp`)

<!-- project: examples/book/ch20-libraries/addressbook/addressbook.bbp -->
```basic
Private Sub saveButton_Click()
    If Trim(nameField.Text) = "" Then
        status.Caption = "A contact needs a name"
        Exit Sub
    End If
    If currentId = 0 Then
        db.Execute "INSERT INTO contact (name, phone, email, notes) VALUES (?, ?, ?, ?)", _
                   Trim(nameField.Text), phoneField.Text, emailField.Text, notesField.Text
        currentId = db.LastInsertId
        status.Caption = "Added " & Trim(nameField.Text)
    Else
        db.Execute "UPDATE contact SET name = ?, phone = ?, email = ?, notes = ? WHERE id = ?", _
                   Trim(nameField.Text), phoneField.Text, emailField.Text, notesField.Text, currentId
        status.Caption = "Saved " & Trim(nameField.Text)
    End If
    LoadList currentId
End Sub
```

### Errors

| Error | When |
|---|---|
| 31601 | SQLite reported an error. `Err.Description` has its message (`UNIQUE constraint failed: player.name`, `near "SELEKT": syntax error`, `no such table: x`) and `ErrorCode` its number. Also: a closed database, a read-only one, a file that can't be opened, `MoveNext` past the end. |
| 450 | the number of values doesn't match the number of `?` marks, or parameters in a text with several statements |
| 5 | an unknown column name in `rs(...)` |
| 9 | a column position out of range |
| 13 | a value that can't be stored, such as an object |
| 380 | a negative `Timeout` |

*Listing 20.87* (`examples/book/ch20-libraries/sqlerrors/sqlerrors.bbp`)

<!-- project: examples/book/ch20-libraries/sqlerrors/sqlerrors.bbp -->
```basic
' sqlerrors.bas - SQLite's own errors (31601) and the others
Option Explicit
Dim db As SQLite, rs As SqlRecordset, v As Variant

Set db = CreateObject("SQLite")
db.Open ":memory:"
db.Execute "CREATE TABLE player (name TEXT UNIQUE)"
db.Execute "INSERT INTO player VALUES (?)", "Ann"
On Error Resume Next
db.Execute "INSERT INTO player VALUES (?)", "Ann"
Print Err.Number; Err.Description; " (code"; db.ErrorCode; ")"
Err.Clear
db.Execute "SELEKT * FROM player"
Print Err.Number; Err.Description
Err.Clear
v = db.QueryValue("SELECT * FROM nowhere")
Print Err.Number; Err.Description
Err.Clear
db.Execute "INSERT INTO player VALUES (?)", "Bob", "Cy"
Print Err.Number; Err.Description
Err.Clear
Set rs = db.Query("SELECT name FROM player")
v = rs("age")
Print Err.Number; Err.Description
Err.Clear
v = rs(3)
Print Err.Number; Err.Description
Err.Clear
rs.MoveNext
rs.MoveNext
Print Err.Number; Err.Description
Err.Clear
rs.Close
db.Execute "INSERT INTO player VALUES (?)", db
Print Err.Number; Err.Description
Err.Clear
db.Timeout = -1
Print Err.Number; Err.Description
Err.Clear
db.Close
v = db.QueryValue("SELECT 1")
Print Err.Number; Err.Description
Err.Clear
db.Open "no-such-drawer/x.db"
Print Err.Number; Err.Description
```

```output
 31601 UNIQUE constraint failed: player.name (code 2067 )
 31601 near "SELEKT": syntax error
 31601 no such table: nowhere
 450 the statement has 1 parameter(s) (?) but 2 value(s) were given
 5 no column named age
 9 Subscript out of range
 31601 MoveNext past the last row (check AtEnd)
 13 a query parameter must be a number, a String, a Date, Null or Empty
 380 Invalid property value
 31601 the database isn't open (Open)
 31601 can't open no-such-drawer/x.db: unable to open database file
```

### Limits and gotchas

- Only one program can write to a database at a time. Another program that tries waits for
  `Timeout` milliseconds, then gets error 31601 ("database is locked").
- Close a recordset (or let it go) before you run its prepared statement again, and before you
  close the database: an open recordset keeps the file in use.
- A Boing BASIC String is bytes: text is stored as it is, Latin-1 on the Amiga. A database made
  on another computer usually holds UTF-8 text: convert it with `Utf8Decode` (see
  [Text encodings](#text-encodings)).
- `LIKE` ignores case only for the letters A-Z, not for accented letters.
- The database files are the same everywhere: copy one between the Amiga and another computer
  and open it there, with the `sqlite3` command-line tool, DB Browser for SQLite, or Python.

## Summary

- `Dictionary` maps keys to values; `JsonParse` turns JSON text into Dictionaries and arrays,
  and `JsonStringify` back.
- `Utf8Decode`/`Utf8Encode` convert between the web's UTF-8 and the Amiga's Latin-1; Base64,
  URL and hex encodings are there too.
- `Crc32`, `Md5`, `Sha1`, `Sha256` and the HMAC functions check and sign data.
- `NowUtc`, `UnixTime`, `FormatIso8601` and friends handle times the way web services expect.
- Build long strings with a `StringBuilder`.
- `RegExp` matches, extracts and replaces text by patterns.
- `Csv` reads and writes CSV files; `CreateUUID` makes unique IDs; `Process` runs Shell commands
  and captures their output.
- `IniFile` reads and writes settings files; `Logger` writes leveled log messages.
- `XmlDocument` reads, changes and writes XML; `Compress`/`Decompress` and `Zip` handle
  compressed data and archives.
- `SQLite` keeps data in an SQL database file: `Execute`, `Query` and prepared statements with
  `?` parameters, and transactions. It is a standard extension: the project needs
  `Extension=sqlite`.

See also: [Networking](19-networking.md) for fetching the data, [Built-in functions](09-builtins.md)
and [Files](10-files.md).
