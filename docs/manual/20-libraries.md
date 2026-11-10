# Modern libraries

Programs today juggle data that comes from the internet and goes back to it: lookups by name,
JSON documents, text in UTF-8, checksums and signatures, dates in UTC. This chapter describes
the libraries Boing BASIC has for them. They are part of the runtime, so they work the same in
the interpreter and in native programs, on AmigaOS 4 and on macOS and Linux:

| Library | What it is for |
|---|---|
| [Dictionary](#dictionary) | a table of values looked up by key |
| [JSON](#json) | reading and writing JSON text |
| [Text encodings](#text-encodings) | UTF-8, Base64, URL and hex encoding |
| [Checksums and hashes](#checksums-and-hashes) | CRC32, MD5, SHA-1, SHA-256 and HMAC signatures |
| [Dates and times in UTC](#dates-and-times-in-utc) | UTC, Unix time and ISO 8601 dates |
| [StringBuilder](#stringbuilder) | building long strings quickly |

Each library's classes are created with `New` or `CreateObject` like the runtime's other
objects; its functions are called like built-in functions. One rule applies to all of them:
names in Boing BASIC aren't case-sensitive, so a module or variable named like a class hides it.
Don't call a program `dictionary.bas`, or a variable `stringbuilder`.

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

Arrays are values, objects are references. You can't change one element of an array inside a
Dictionary in place (`user("langs")(1) = "Pascal"` is error 424): read the array into a
variable, change it, and store it back with `user("langs") = langs`.

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

- **Don't call a module `dictionary.bas`.** A module takes its name from its file, and a
  module named `Dictionary` hides the class: `Dim d As Dictionary` then stops with "type
  'Dictionary' is not defined". The same goes for `stringbuilder.bas` and `http.bas`. Call
  the file `wordcount.bas`, `stock.bas` or similar.
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

- Don't call a module `stringbuilder.bas`: it hides the class (see [Dictionary](#dictionary)).
- `Append` and `AppendLine` return the StringBuilder. Called as a statement
  (`sb.Append "x"`) the result is simply dropped; that is fine.
- `AppendLine` adds a line feed only, the Amiga's line end. For text that must have CR LF line
  ends (some Internet protocols, files for Windows), use `sb.Append x, vbCrLf`.
- `Replace` and `Char` work on bytes and are case-sensitive.

## Summary

- `Dictionary` maps keys to values; `JsonParse` turns JSON text into Dictionaries and arrays,
  and `JsonStringify` back.
- `Utf8Decode`/`Utf8Encode` convert between the web's UTF-8 and the Amiga's Latin-1; Base64,
  URL and hex encodings are there too.
- `Crc32`, `Md5`, `Sha1`, `Sha256` and the HMAC functions check and sign data.
- `NowUtc`, `UnixTime`, `FormatIso8601` and friends handle times the way web services expect.
- Build long strings with a `StringBuilder`.

See also: [Networking](19-networking.md) for fetching the data, [Built-in functions](09-builtins.md)
and [Files](10-files.md).
