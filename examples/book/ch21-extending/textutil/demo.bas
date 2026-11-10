' demo.bas - uses the textutil extension (Extension=textutil in demo.bbp)
Sub Main()
    Dim wc As WordCount
    Set wc = CreateObject("WordCount")
    wc.Add "The ball bounces. The ball spins, and the ball falls."
    wc.Add "A red and white ball!"
    Print wc.Total; "words,"; wc.Distinct; "different"
    Print "ball:"; wc.Count("Ball"); " the:"; wc.Count("THE"); " amiga:"; wc.Count("amiga")
    Print "Top 3: "; wc.Top(3)
    Print WordTotal("one two  three")
End Sub
