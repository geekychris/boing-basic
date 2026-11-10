Option Explicit
Dim stock As Dictionary, item As Variant
Set stock = CreateObject("Dictionary")
stock("apples") = 12                    ' adds the key "apples"
stock("pears") = 7
stock("apples") = stock("apples") - 2   ' changes its value
Print stock("apples"); stock.Count
For Each item In stock
    Print item; ": "; stock(item)
Next
