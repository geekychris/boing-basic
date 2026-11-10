' Use: a setting for this session; GetSetting finds it like a saved one
UseSetting "BoingDemo", "View", "Zoom", "200"
Print GetSetting("BoingDemo", "View", "Zoom", "100")
DeleteSetting "BoingDemo"
Print GetSetting("BoingDemo", "View", "Zoom", "100")
