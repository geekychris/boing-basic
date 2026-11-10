Option Explicit
Dim c As Collection, v As Variant, o As Object
Print c Is Nothing; IsObject(c); TypeName(c)
Set c = New Collection
Print c Is Nothing; TypeName(c); TypeOf c Is Collection
Set o = c
Print o Is c; TypeName(o)
v = 42
Print IsObject(v); TypeName(v)
Set v = c
Print IsObject(v); TypeName(v)
Set c = Nothing
Print o.Count; "items: o still holds the object"
