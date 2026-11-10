Option Explicit
Dim colours As Dictionary
Set colours = CreateObject("Dictionary")
colours.CompareMode = 1
colours("Red") = RGB(255, 0, 0)
colours("Green") = RGB(0, 255, 0)
Print Hex(colours("RED")), colours.Exists("green"), colours.Keys()(0)
