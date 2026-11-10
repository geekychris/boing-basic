' GetSetting / SaveSetting / DeleteSetting (docs/ui.md) and the App object's late-bound members
SaveSetting "BoingTest", "Window", "Left", "120"
SaveSetting "BoingTest", "Window", "Top", "45"
SaveSetting "BoingTest", "Recent", "File1", "Work:a picture.iff"
Print GetSetting("BoingTest", "Window", "Left", "0")
Print GetSetting("BoingTest", "Recent", "File1")
Print GetSetting("BoingTest", "Window", "Width", "640")
DeleteSetting "BoingTest", "Window", "Left"
Print GetSetting("BoingTest", "Window", "Left", "deleted")
Print GetSetting("BoingTest", "Window", "Top")
DeleteSetting "BoingTest", "Window"
Print GetSetting("BoingTest", "Window", "Top", "section deleted")
DeleteSetting "BoingTest"
Print GetSetting("BoingTest", "Recent", "File1", "app deleted")
On Error Resume Next
SaveSetting "", "a", "b", "c"
Print Err.Number
On Error GoTo 0
Print App.ToolType("WIDTH", "640")
Print App.FromWorkbench
Print App.Str(12, "Open...")
UseSetting "BoingUse", "S", "K", "used"
Print GetSetting("BoingUse", "S", "K", "none")
DeleteSetting "BoingUse"
Print GetSetting("BoingUse", "S", "K", "gone")
