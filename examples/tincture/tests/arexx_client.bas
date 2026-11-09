' arexx_client.bas - sends ARexx commands to a running Tincture's port (App.SendARexx, the
' same messages an ARexx script sends) and prints the replies (tools/guest.py arexx)
Dim r As String
Print "version "; App.SendARexx("TINCTURE", "VERSION")
r = App.SendARexx("TINCTURE", "NEW 64 48")
r = App.SendARexx("TINCTURE", "COLOR 255 0 0")
r = App.SendARexx("TINCTURE", "BOX 0 0 10 10")
Print "pixel "; App.SendARexx("TINCTURE", "GETPIXEL 5 5")
r = App.SendARexx("TINCTURE", "LAYER ADD Ink")
Print "info "; App.SendARexx("TINCTURE", "INFO")
r = App.SendARexx("TINCTURE", "FROB")
Print "rc "; App.ARexxRC; " "; r
r = App.SendARexx("TINCTURE", "QUIT")
Print "done"
