' a program file named err.bas (module err): Err, Err.Number and Err.Raise are still the Err object
On Error Resume Next
x = 1 / 0
Print Err; Err.Number; Err.Description
If Err Then Print "set"
Err.Clear
Err.Raise 5
Print Err.Number
