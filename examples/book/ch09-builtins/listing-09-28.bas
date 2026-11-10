Dim t As Integer, r As Variant
For t = -5 To 35 Step 20
    Print t; Switch(t < 0, "freezing", t < 20, "mild", t < 30, "warm")
Next
r = Switch(t > 100, "boiling")
Print IsNull(r)
