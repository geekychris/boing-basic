Dim all As Variant, i As Integer
SaveSetting "BoingDemo", "Window", "Width", "640"
SaveSetting "BoingDemo", "Window", "Height", "480"
SaveSetting "BoingDemo", "Window", "Left", "20"
all = GetAllSettings("BoingDemo", "Window")
For i = LBound(all, 1) To UBound(all, 1)
    Print all(i, 0); " = "; all(i, 1)
Next
DeleteSetting "BoingDemo"
Print IsEmpty(GetAllSettings("BoingDemo", "Window"))
