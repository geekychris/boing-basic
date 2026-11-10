' Numbers in the user's own format; on a host: "." and ","
Option Explicit
Print App.FormatNumber(1234567.891)
Print App.FormatNumber(-42.5, 1)
Print App.FormatNumber(1999, 0)
Print "Point "; App.DecimalPoint; ", separator "; App.GroupSeparator
