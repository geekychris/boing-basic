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
