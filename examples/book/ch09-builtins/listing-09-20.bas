Dim t As Double, i As Long, total As Double
Print "Today is "; Format(Date, "dddd d mmmm yyyy"); ", the time is "; Format(Time, "hh:nn")
t = TimerMs
For i = 1 To 100000
    total = total + Sqr(i)
Next
Print "That took"; Int(TimerMs - t); "ms"
