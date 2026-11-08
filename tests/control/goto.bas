Dim n As Integer
n = 0
10 n = n + 1
If n < 3 Then GoTo 10
Print "n ="; n
GoSub sayhi
GoSub sayhi
GoTo skip
Print "not printed"
skip:
On 2 GoTo a1, a2, a3
a1:
Print "a1"
a2:
Print "a2"
a3:
Print "a3"
On 3 GoSub g1, g2, g3
Print "back"
End
sayhi:
Print "hi"
Return
g1: Print "g1": Return
g2: Print "g2": Return
g3: Print "g3": Return
