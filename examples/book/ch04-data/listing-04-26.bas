Enum Fruit
    Apple           ' 0
    Pear            ' 1
    Plum = 10
    Fig             ' 11
    Kiwi = -1
End Enum

Dim f As Fruit
f = Fig
Print Apple; Pear; Plum; f; Fruit.Kiwi
Print TypeName(f)
