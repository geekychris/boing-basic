Dim fruit() As String, hits() As String
fruit = Split("apple,Banana,cherry,grape,PEAR", ",")
hits = Filter(fruit, "an")
Print UBound(hits) + 1; "with an: "; Join(hits, " ")
hits = Filter(fruit, "e", False)
Print UBound(hits) + 1; "without e: "; Join(hits, " ")
hits = Filter(fruit, "AP", True, vbTextCompare)
Print UBound(hits) + 1; "with ap, any case: "; Join(hits, " ")
Print UBound(Filter(fruit, "kiwi"))
