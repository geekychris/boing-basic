Option Explicit
Dim pic As Object
Set pic = CreateObject("Boing.Canvas")      ' an off-screen picture, 320 x 200
Print TypeName(pic); pic.Width; pic.Height
pic.PSet 10, 10, RGB(255, 0, 0)
Print Hex(pic.Point(10, 10))

Dim cv As Canvas                            ' typed: early bound
Set cv = CreateObject("Boing.Canvas")
cv.Cls
Print cv.Width

On Error Resume Next
Dim x As Object
Set x = CreateObject("Boing.Spreadsheet")
Print Err.Number; Err.Description
