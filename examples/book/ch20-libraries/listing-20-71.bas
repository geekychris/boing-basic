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
