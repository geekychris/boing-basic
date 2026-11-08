Dim name As String, age As Integer, a As Variant, b As Variant, line As String
Input "Name"; name
Input "Age: ", age
Print "Hello "; name; ", next year you are"; age + 1
Input a, b
Print a; "+"; b; "="; a + b; TypeName(a)
Line Input line
Print "["; line; "]"
Line Input "prompt> "; line
Print "["; line; "]"
Print MsgBox("Continue?", vbYesNo + vbQuestion, "Question") = vbYes
Print MsgBox("just ok")
Print InputBox("Your colour?", "Survey", "blue")
Print InputBox("Default?", , "fallback")
