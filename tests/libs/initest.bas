' IniFile: reading, values with defaults, changes keeping comments and order, sections/keys
Option Explicit
Dim ini As IniFile, s As String, a, i As Long, ok As Boolean

Set ini = CreateObject("IniFile")
s = "; game settings" & vbLf & "version = 2" & vbLf & vbLf & _
    "[Video]" & vbLf & "Width=640" & vbLf & "height = 480 " & vbLf & "; fullscreen is risky" & vbLf & "Mode=""  spaced  """ & vbLf & vbLf & _
    "[Sound]" & vbLf & "Volume=50" & vbLf & "# a hash comment" & vbLf & "Device=ahi.device"
ini.LoadText s
Print ini.Value("", "version"); " "; ini.Value("video", "WIDTH"); " ["; ini.Value("Video", "Height"); "] ["; ini.Value("Video", "Mode"); "]"
Print "["; ini.Value("Video", "Depth"); "] ["; ini.Value("Video", "Depth", "8"); "] ["; ini.Value("Nope", "x", "def"); "]"
Print Join(ini.Sections, "|"); " / "; Join(ini.Keys("Video"), "|"); " / "; UBound(ini.Keys("None"))
Print ini.HasSection("SOUND"); ini.HasSection("Net"); ini.HasSection(""); ini.HasKey("Sound", "volume"); ini.HasKey("Sound", "x")
Print "changed:"; ini.Changed
ini.Value("Video", "Width") = 800
ini.Value("Video", "Depth") = 24
ini.Value("Net", "Host") = "amiga.local"
ini.Value("", "author") = "me"
ini.Value("Sound", "Volume") = " 70 "
ini.Value("Sound", "Volume") = " 70 "
Print "changed:"; ini.Changed
Print ini.DeleteKey("Sound", "Device"); ini.DeleteKey("Sound", "Device")
Print Replace(ini.Text, vbLf, "\n")
Print ini.DeleteSection("Video"); ini.DeleteSection("Video")
Print Replace(ini.Text, vbLf, "\n")

' files: load (missing = empty), save, reload; CRLF files stay CRLF
On Error Resume Next
Kill "initest.tmp"
On Error GoTo 0
ok = ini.Load("initest.tmp")
Print "missing:"; ok; UBound(ini.Sections)
ini.Value("App", "Runs") = 1
ini.Save
Set ini = CreateObject("IniFile")
Print "loaded:"; ini.Load("initest.tmp"); ini.Value("App", "Runs"); " "; ini.Path
ini.Value("App", "Runs") = CLng(ini.Value("App", "Runs")) + 1
ini.Save
ini.Load "initest.tmp"
Print "runs:"; ini.Value("App", "Runs")
ini.LoadText "[A]" & vbCrLf & "x=1" & vbCrLf
ini.Value("A", "y") = 2
Print Replace(Replace(ini.Text, vbCr, "\r"), vbLf, "\n")
ini.Save "initest.tmp"
Open "initest.tmp" For Binary As #1
Print "bytes:"; LOF(1)
Close #1
Kill "initest.tmp"
ini.Clear
Print "cleared:["; ini.Text; "]"; UBound(ini.Sections)

' errors
On Error Resume Next
ini.Value("A", "bad=key") = 1
Print "key:"; Err.Number: Err.Clear
ini.Value("A", "k") = "two" & vbLf & "lines"
Print "value:"; Err.Number: Err.Clear
ini.Load "no-such-file.ini", True
Print "must exist:"; Err.Number: Err.Clear
Set ini = CreateObject("IniFile")
ini.Save
Print "no name:"; Err.Number: Err.Clear
