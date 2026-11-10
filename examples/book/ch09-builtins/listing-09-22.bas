Dim d As Date
d = #1/31/2024 10:00:00 AM#
Print DateAdd("m", 1, d); " | "; DateAdd("yyyy", -1, d); " | "; DateAdd("ww", 2, d)
Print DateAdd("h", 36, d); " | "; DateAdd("n", -90, d)
Print DateDiff("d", #1/1/2024#, #3/1/2024#); DateDiff("m", #11/15/2023#, #2/1/2024#)
Print DateDiff("yyyy", #12/31/2023#, #1/1/2024#); DateDiff("h", #1/1/2024#, #1/2/2024 6:00:00 AM#)
Print DatePart("q", #8/15/2024#); DatePart("y", #2/1/2024#); DatePart("ww", #2/1/2024#)
