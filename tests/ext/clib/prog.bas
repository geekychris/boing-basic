Declare Function AddMul Lib "C" (ByVal a As Long, ByVal b As Long, ByVal c As Long) As Long
Declare Function Hypot2 Lib "C" (ByVal x As Double, ByVal y As Double) As Double
Declare Function StrLenC Lib "C" (ByVal s As String) As Long
Declare Function Greet Lib "C" (ByVal n As Long) As String
Declare Sub Nop Lib "C" ()
Sub Main()
    Print AddMul(2, 3, 4); Hypot2(3, 4); StrLenC("hello"); Greet(5); " "; Greet(-1)
    Nop
End Sub
