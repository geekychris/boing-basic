Dim src(2) As Integer, copy() As Integer
src(0) = 7: src(1) = 8: src(2) = 9
copy = src
src(0) = 0
Print copy(0); copy(2); UBound(copy)
