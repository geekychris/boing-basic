# Dictionary: keys and values

A `Dictionary` maps keys to values: look up a price by product name, count words, keep settings
by name, hold the objects of a parsed JSON document. Lookups take the same time however many
entries there are, and the entries keep the order they were added in.

```basic
Dim stock As Dictionary
Set stock = CreateObject("Dictionary")
stock("apples") = 12              ' add
stock("pears") = 7
stock("apples") = stock("apples") - 2   ' change
Print stock("apples"); stock.Count      ' 10  2
For Each item In stock
    Print item; ": "; stock(item)
Next
```

## Keys

A key is a **string**, a **number** or an **object**.

- Numbers compare by value whatever their type: `1`, `1&`, `1#` and `1.0` are the same key.
  The string `"1"` is a different key from the number `1`.
- Objects are keys by identity: two different objects are two keys even if they hold the same
  things.
- `Empty` is a key too (one key). `Null` and arrays can't be keys (error 5).
- String keys are case-sensitive unless `CompareMode` is 1.

Values can be anything: numbers, strings, arrays, objects, other Dictionaries.

## Members

| Member | |
|---|---|
| `Item(key)` | the value for `key`; the default member, so `d(key)` is the same. Reading a key that isn't there gives `Empty` (and doesn't add it). Assigning adds the key or replaces its value; use `Set d(key) = obj` for objects |
| `Add key, value` | adds a key that must not be there yet (error 457 if it is) |
| `Exists(key)` | True if the key is there |
| `Remove key` | removes it (error 5 if it isn't there) |
| `RemoveAll` | removes everything |
| `Count` | the number of entries |
| `Keys()` | the keys as an array (0 to Count - 1), in insertion order |
| `Items()` | the values as an array, in the same order |
| `Key(old) = new` | renames a key, keeping its value and its place |
| `CompareMode` | 0 (default): string keys are case-sensitive; 1: they aren't (Latin-1 letters too: `"Ä"` and `"ä"` are one key). Can only be changed while the Dictionary is empty |

`For Each k In d` goes through the keys in insertion order. Don't add or remove entries inside
such a loop; loop over `d.Keys` instead when you need to.

## Examples

```basic
' counting: a missing key reads as Empty, and Empty + 1 is 1
counts(word) = counts(word) + 1

' a lookup table with case-insensitive keys
Set colours = CreateObject("Dictionary")
colours.CompareMode = 1
colours("Red") = RGB(255, 0, 0)
Print Hex(colours("RED"))

' nested: a Dictionary of Dictionaries
Set user = CreateObject("Dictionary")
Set user("address") = CreateObject("Dictionary")
user("address")("city") = "Amsterdam"
```

`examples/wordcount/wordcount.bas` counts the words of a text file and prints the most common
ones.

## Notes

- A program module named `Dictionary` (a file `dictionary.bas`) hides the class: name your
  files differently.
- `Dim d As Dictionary` then `Set d = CreateObject("Dictionary")`
  (`CreateObject("Boing.Dictionary")` works too).

## Tests

`tests/lib/dicttest.bas` (in `make test`, through the VM and as a native build): adding,
replacing, reading missing keys, insertion order, removal, numeric keys of mixed types, object
keys, nested values, `CompareMode`, renaming, the error cases, and 25000 keys with removals
(growth and compaction). On the AmigaOS 4 guest (`tools/os4guest.py outtest
tests/lib/dicttest.bas`): identical output, VM and native.
