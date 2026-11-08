' Sorting algorithms on Long and String arrays
Option Explicit

Sub BubbleSort(a() As Long)
    Dim i As Long, j As Long, t As Long, swapped As Boolean
    For i = UBound(a) To LBound(a) + 1 Step -1
        swapped = False
        For j = LBound(a) To i - 1
            If a(j) > a(j + 1) Then
                t = a(j): a(j) = a(j + 1): a(j + 1) = t
                swapped = True
            End If
        Next j
        If Not swapped Then Exit For
    Next i
End Sub

Sub QuickSort(a() As Long, ByVal lo As Long, ByVal hi As Long)
    Dim i As Long, j As Long, pivot As Long, t As Long
    If lo >= hi Then Exit Sub
    pivot = a((lo + hi) \ 2)
    i = lo: j = hi
    Do While i <= j
        Do While a(i) < pivot: i = i + 1: Loop
        Do While a(j) > pivot: j = j - 1: Loop
        If i <= j Then
            t = a(i): a(i) = a(j): a(j) = t
            i = i + 1: j = j - 1
        End If
    Loop
    QuickSort a, lo, j
    QuickSort a, i, hi
End Sub

Sub InsertionSortStr(s() As String)
    Dim i As Long, j As Long, key As String
    For i = LBound(s) + 1 To UBound(s)
        key = s(i)
        j = i - 1
        Do While j >= LBound(s)
            If StrComp(s(j), key, vbTextCompare) <= 0 Then Exit Do
            s(j + 1) = s(j)
            j = j - 1
        Loop
        s(j + 1) = key
    Next
End Sub

Function MergeSorted(a() As Long) As Long()
    Dim n As Long, mid_ As Long, i As Long, l() As Long, r() As Long, res() As Long
    Dim li As Long, ri As Long, k As Long
    n = UBound(a) - LBound(a) + 1
    If n <= 1 Then
        MergeSorted = a
        Exit Function
    End If
    mid_ = n \ 2
    ReDim l(mid_ - 1)
    ReDim r(n - mid_ - 1)
    For i = 0 To mid_ - 1: l(i) = a(LBound(a) + i): Next
    For i = 0 To n - mid_ - 1: r(i) = a(LBound(a) + mid_ + i): Next
    l = MergeSorted(l)
    r = MergeSorted(r)
    ReDim res(n - 1)
    Do While li <= UBound(l) And ri <= UBound(r)
        If l(li) <= r(ri) Then
            res(k) = l(li): li = li + 1
        Else
            res(k) = r(ri): ri = ri + 1
        End If
        k = k + 1
    Loop
    Do While li <= UBound(l): res(k) = l(li): li = li + 1: k = k + 1: Loop
    Do While ri <= UBound(r): res(k) = r(ri): ri = ri + 1: k = k + 1: Loop
    MergeSorted = res
End Function

Function Show(a() As Long) As String
    Dim i As Long, s As String
    For i = LBound(a) To UBound(a)
        If i > LBound(a) Then s = s & " "
        s = s & a(i)
    Next
    Show = s
End Function

Function IsSorted(a() As Long) As Boolean
    Dim i As Long
    For i = LBound(a) To UBound(a) - 1
        If a(i) > a(i + 1) Then Exit Function
    Next
    IsSorted = True
End Function

Dim data() As Long, copy1() As Long, i As Long, seed As Long
ReDim data(1 To 12)
seed = 12345
For i = 1 To 12
    seed = (seed * 1103 + 12849) Mod 65536
    data(i) = seed Mod 100
Next
Print "data:  "; Show(data)
copy1 = data
BubbleSort copy1
Print "bubble:"; " "; Show(copy1)
copy1 = data
QuickSort copy1, LBound(copy1), UBound(copy1)
Print "quick: "; Show(copy1)
Dim m() As Long
m = MergeSorted(data)
Print "merge: "; Show(m); " "; LBound(m)
Print IsSorted(copy1); IsSorted(data)

Dim big() As Long
ReDim big(1 To 2000)
For i = 1 To 2000
    seed = (seed * 1103 + 12849) Mod 65536
    big(i) = seed
Next
QuickSort big, 1, 2000
Print "big sorted:"; IsSorted(big); big(1) <= big(2000)

Dim words() As String
words = Split("pear Apple banana cherry apple Date fig", " ")
InsertionSortStr words
Print Join(words, ",")
