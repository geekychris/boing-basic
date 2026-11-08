Dim d As Date, d2 As Date
d = #2/28/2000#
Print d; Year(d); Month(d); Day(d); Weekday(d)
d = DateAdd("d", 1, d)
Print d
d = DateAdd("m", 1, #1/31/2001#)
Print d
d = DateSerial(2024, 13, 1)
Print d
d = DateSerial(2024, 3, 0)
Print d
Print DateDiff("d", #1/1/2000#, #3/1/2000#); DateDiff("m", #11/15/1999#, #2/1/2000#); DateDiff("yyyy", #12/31/1999#, #1/1/2000#)
d = #10:30:15 AM#
Print d; Hour(d); Minute(d); Second(d)
d = #1/2/2003 4:05:06 PM#
Print d
d2 = d + 0.5
Print d2
Print TimeSerial(13, 5, 0)
Print MonthName(2); " "; MonthName(11, True); " "; WeekdayName(1); " "; WeekdayName(7, True)
Print Format(#7/4/1976#, "dddd, mmmm d, yyyy"); " | "; Format(#7/4/1976#, "dd/mm/yy")
Print Format(#7/4/1976 21:07:09#, "hh:nn:ss AM/PM"); " | "; Format(#7/4/1976 21:07:09#, "h:nn")
Print DatePart("q", #8/15/2020#); DatePart("y", #2/1/2020#); DatePart("w", #8/15/2020#)
Print CDate("2021-06-15") + 1; IsDate("1/2/2003"); IsDate("hello")
Print CDbl(#1/1/1900#); CLng(#12/31/1899#)
Print Year(Now) > 2000; Timer >= 0
