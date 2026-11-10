Dim d As Date
d = DateSerial(2024, 3, 9) + TimeSerial(14, 5, 9)
Print Year(d); Month(d); Day(d); Hour(d); Minute(d); Second(d)
Print Weekday(d); WeekdayName(Weekday(d)); " "; MonthName(Month(d)); " "; MonthName(Month(d), True)
Print Weekday(d, vbMonday); WeekdayName(Weekday(d), True)
Print DateSerial(2024, 2, 30); " | "; DateSerial(2024, 3, 0); " | "; DateSerial(24, 13, 1)
Print DateValue(d); " | "; TimeValue(d); " | "; TimeSerial(0, 90, 0)
