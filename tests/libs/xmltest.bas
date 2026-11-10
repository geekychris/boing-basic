' XmlDocument / XmlElement: parse, navigate, edit, write, errors
Option Explicit
Dim doc As XmlDocument, root As XmlElement, e As XmlElement, it, s As String, i As Long

Set doc = CreateObject("XmlDocument")
s = "<?xml version=""1.0"" encoding=""ISO-8859-1""?>" & vbLf & _
    "<!DOCTYPE rss [ <!ENTITY x ""y""> ]>" & vbLf & _
    "<!-- a feed -->" & vbLf & _
    "<rss version='2.0'>" & vbLf & _
    "  <channel>" & vbLf & _
    "    <title>Boing &amp; friends</title>" & vbLf & _
    "    <item id=""1""><title>First &lt;one&gt;</title><link>http://a/?x=1&amp;y=2</link></item>" & vbLf & _
    "    <item id=""2"" new=""yes""><title><![CDATA[Second <b>bold</b>]]></title><empty/></item>" & vbLf & _
    "    <item id=""3""><title>Caf&#233; &#x263A;</title><p>mixed <b>bold</b> text</p></item>" & vbLf & _
    "  </channel>" & vbLf & _
    "</rss>"
doc.LoadXml s
Set root = doc.Root
Print root.Name; " "; root.Attribute("version"); " "; root.ChildCount; " "; TypeName(root); " "; TypeName(doc)
Set e = root.Child("channel")
Print e.ChildText("title"); " | "; e.ChildCount; " items:"; e.FindAll("item").Count
For Each it In doc.FindAll("item")
    Print it.Attribute("id"); " ["; it.ChildText("title"); "] new="; it.Attribute("new", "no"); " "; it.HasAttribute("new")
Next
Print Len(doc.Find("item").Child("link").Text); " "; doc.Find("link").Text
Print Asc(Mid(doc.FindAll("title")(3).Text, 4, 1)); Len(doc.FindAll("title")(3).Text)
Print doc.Find("p").Text; " | "; doc.Find("p").InnerXml
Print root.SelectNodes("channel/item/title").Count; root.SelectNodes("channel/*").Count; root.SelectNodes("item").Count
Print doc.Find("nothing") Is Nothing; doc.Find("empty").ChildCount; "["; doc.Find("empty").Text; "]"
Print Join(doc.FindAll("item")(1).AttributeNames, ",")
Print doc.Find("empty").Parent.Attribute("id"); " "; doc.Find("item").Parent.Name; root.Parent Is Nothing

' editing
Set e = doc.Find("channel").AddElement("item")
e.Attribute("id") = 4
e.AddElement "title", "Fourth: <5> & ""quoted"""
e.AddElement("link").Text = "x"
doc.FindAll("item")(0).Remove
doc.Find("item").RemoveAttribute "new"
doc.Find("title").Text = "Renamed"
doc.Find("channel").Child("item").Name = "entry"
doc.Find("p").Remove
Print doc.Root.Xml

' building a document from nothing, unindented
Set doc = CreateObject("XmlDocument")
Set root = doc.CreateRoot("config")
root.Attribute("v") = "1 < 2 & ""3"""
root.AddElement("name", "Boing").Attribute("lang") = "en"
Set e = doc.CreateElement("list")
For i = 1 To 3
    e.AddElement("n", CStr(i))
Next
root.AppendChild e
root.InsertBefore doc.CreateElement("first"), root.Child("name")
doc.Indent = False
Print doc.Xml
doc.Indent = True
doc.Save "xmltest.tmp"
Set doc = CreateObject("XmlDocument")
doc.Load "xmltest.tmp"
Print doc.Root.Attribute("v"); " "; doc.Find("list").ChildCount; " "; doc.Find("first").Parent.Name
Print doc.Xml
Kill "xmltest.tmp"

' errors
On Error Resume Next
Dim bad
bad = Array("", "<a>", "<a></b>", "<a b=1/>", "<a><b></a>", "<a/><b/>", "text", "<a b=""1"" b2/>", "<a><!-- x</a>")
For i = 0 To UBound(bad)
    doc.LoadXml bad(i)
    Print i; Err.Number; " "; Err.Description
    Err.Clear
Next
doc.LoadXml "<a/>"
doc.Root.AddElement "bad name"
Print "name:"; Err.Number: Err.Clear
doc.Root.AppendChild doc.Root
Print "self:"; Err.Number: Err.Clear
doc.Load "no-such.xml"
Print "load:"; Err.Number: Err.Clear
