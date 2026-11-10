Function Range(ByVal first As Long, ByVal last As Long) As Long()
    Dim r() As Long, i As Long
    ReDim r(first To last)
    For i = first To last
        r(i) = i
    Next
    Range = r
End Function

Dim nums() As Long
nums = Range(5, 9)
Print LBound(nums); UBound(nums); nums(7)
