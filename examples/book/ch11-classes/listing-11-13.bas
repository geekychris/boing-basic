Option Explicit
Dim fruit As New Collection, f As Variant
fruit.Add "apple", "a"              ' item, key
fruit.Add "cherry", "c"
fruit.Add "banana", "b", "c"        ' before the item with key "c"
fruit.Add "date", "d", , 3          ' after the third item
Print fruit.Count; "items"
For Each f In fruit
    Print f; " ";
Next
Print
Print fruit(1); " "; fruit("B"); " "; fruit.Item("c"); " "; fruit!d
fruit.Remove "a"                    ' by key
fruit.Remove 1                      ' by position
Print fruit.Count; fruit(1)
