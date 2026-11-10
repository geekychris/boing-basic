Dim fruit As String, t As Double
fruit = "mango"
Select Case fruit
    Case "apple", "pear": Print "orchard fruit"
    Case "kiwi" To "orange": Print "between kiwi and orange"
    Case Else: Print "something else"
End Select
t = 21.5
Select Case True
    Case t < 0: Print "freezing"
    Case t < 15: Print "cold"
    Case t < 25: Print "mild"
    Case Else: Print "hot"
End Select
