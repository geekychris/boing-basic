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
