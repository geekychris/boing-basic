Dim c As New Collection, o As Object
Print o Is Nothing
Set o = c
Print o Is c; TypeName(o)
Set o = Nothing
Print o Is Nothing
