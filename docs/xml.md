# XmlDocument: reading and writing XML

`XmlDocument` reads an XML document into a tree of `XmlElement` objects that a program can walk,
change and write back out: RSS feeds, configuration files, data from web services, SVG.

```basic
Dim doc As XmlDocument, item As XmlElement
Set doc = CreateObject("XmlDocument")
doc.LoadXml web.Get("https://example.com/feed.rss")
For Each item In doc.FindAll("item")
    Print item.ChildText("title"); " - "; item.ChildText("link")
Next
```

## XmlDocument

| Member | |
|---|---|
| `Load path` / `LoadXml text` | reads a document (replacing what was there); error 31401 if it isn't well-formed |
| `Save path` | writes it, with an `<?xml ...?>` declaration (the one read, or `version="1.0" encoding="ISO-8859-1"`) |
| `Xml` | the whole document as text (default member); assigning it is `LoadXml` |
| `Root` | the top element (`Nothing` for an empty document); assigning an element makes it the root |
| `CreateRoot(name)` | a new, empty document with this root element; returns it |
| `CreateElement(name)` | a new element that isn't in the tree yet (put it there with `AppendChild`) |
| `Find(name)` / `FindAll(name)` | the first / every element with this name anywhere in the document (`"*"`: every element) |
| `Indent` | True (default): `Xml`, `Save` and `element.Xml` write one element per line, indented by two spaces; False: everything on one line |

## XmlElement

| Member | |
|---|---|
| `Name` | the tag name (can be changed) |
| `Text` | all the text inside, child elements' text included (default member). Assigning replaces everything inside with this text. |
| `Attribute(name [, default])` | an attribute's value; default (or "") if it isn't there. `e.Attribute("id") = 7` sets it. |
| `HasAttribute(name)`, `RemoveAttribute(name)` | |
| `AttributeNames` | the attribute names as an array |
| `Children` | the child elements, as a list (`Count`, `Item(i)` from 0, `For Each`) |
| `ChildCount` | how many child elements |
| `Child(name)` | the first child element with this name, or `Nothing` |
| `ChildText(name [, default])` | that child's text; default (or "") if there is no such child |
| `Find(name)` / `FindAll(name)` | the first / every element with this name below this one, at any depth |
| `SelectNodes(path)` | the elements along a path of child names: `"channel/item/title"`; `*` matches any name |
| `Parent` | the element this one is in (`Nothing` for the root) |
| `AddElement(name [, text])` | adds a new child element at the end and returns it |
| `AppendChild(element)` | moves an element (new, or from elsewhere in the document) to the end of this one; returns it |
| `InsertBefore(element, child)` | the same, placed before one of this element's children |
| `RemoveChild(element)`, `Remove` | takes an element out of the tree |
| `Xml` | the element with everything inside as text |
| `InnerXml` | what is inside the element, as text |
| `Document` | the XmlDocument the element belongs to |

An element object stays usable after it is removed (and can be put back with `AppendChild`).
Elements of one document can't be moved to another.

```basic
' build a document
Dim doc As XmlDocument, root As XmlElement, item As XmlElement
Set doc = CreateObject("XmlDocument")
Set root = doc.CreateRoot("highscores")
For i = 1 To 3
    Set item = root.AddElement("score", CStr(points(i)))
    item.Attribute("player") = names(i)
Next
doc.Save "PROGDIR:scores.xml"
```

```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<highscores>
  <score player="Ann">5200</score>
  <score player="Bob">4100</score>
  <score player="Cy">900</score>
</highscores>
```

## What is supported

Elements, attributes (in `"` or `'`), text, `<![CDATA[...]]>` (becomes ordinary text), the
entities `&lt; &gt; &amp; &quot; &apos;` and character references `&#233; &#xE9;`. Comments,
processing instructions and `<!DOCTYPE>` are read past and not kept; text that is only white
space between elements is dropped (so indented files don't produce empty text). Writing escapes
`< > &` in text and also `"` and line breaks in attributes.

**Characters.** Strings are bytes. A character reference below 256 becomes that byte (Latin-1,
as on the Amiga); higher ones are stored as UTF-8. A UTF-8 document's text stays UTF-8. There
are no namespaces (a name like `dc:title` is just a name), no DTD validation and no XPath beyond
`SelectNodes`' simple paths.

## Errors

31401 the text isn't well-formed XML; `Err.Description` says what and on which line ("</b>
doesn't close <a> (line 3)"). 53/75/61 file errors. 5 an invalid element or attribute name, or
an element put inside itself. 9 a list index out of range.

## Tests

`tests/libs/xmltest.bas` (VM, JIT and native in `make test`; on the AmigaOS 4 guest with
`tools/os4guest.py bas tests/libs/xmltest.bas both`).
