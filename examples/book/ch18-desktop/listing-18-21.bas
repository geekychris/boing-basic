' Today's date as the user likes it
Option Explicit
Dim d As Date
d = Now
Print App.FormatDate(d)                   ' the short date, in the user's order
Print App.FormatDate(d, "long")           ' the long date, with names
Print App.FormatDate(d, "time")           ' the time
Print App.FormatDate(d, "datetime")       ' both
Print App.FormatDate(d, "%A %-d %B")      ' for example: Tuesday 10 November
Print App.FormatDate(d, "%Y-%m-%d")       ' for example: 2026-11-10
