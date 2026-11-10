Sub Main()
    Dim c As Counter, x As Long
    Set c = CreateObject("Counter")
    c.Ad 1
    c.Count = 5
    x = Clamp(1, 2)
    x = Clamp(1, 2, 3)
End Sub
