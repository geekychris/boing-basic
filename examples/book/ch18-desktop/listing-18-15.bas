Option Explicit
SaveSetting "Greeter", "Window", "Colour", "blue"
Print GetSetting("Greeter", "Window", "Colour", "grey")
DeleteSetting "Greeter", "Window", "Colour"
Print GetSetting("Greeter", "Window", "Colour", "grey")
