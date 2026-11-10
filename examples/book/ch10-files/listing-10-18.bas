SaveSetting "BoingDemo", "Window", "Left", "120"
SaveSetting "BoingDemo", "Window", "Top", CStr(45)
SaveSetting "BoingDemo", "Recent", "File1", "Work:Pictures/boing.iff"

Print GetSetting("BoingDemo", "Window", "Left", "0")
Print CLng(GetSetting("BoingDemo", "Window", "Top", "0")) + 10
Print GetSetting("BoingDemo", "Window", "Width", "640")
Print GetSetting("BoingDemo", "Recent", "File1")

DeleteSetting "BoingDemo", "Window"
Print GetSetting("BoingDemo", "Window", "Left", "(deleted)")
DeleteSetting "BoingDemo"
