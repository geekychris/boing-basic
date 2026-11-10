Option Explicit
Dim order As Dictionary, customer As Dictionary
Set order = CreateObject("Dictionary")
order("id") = 1001
order("items") = Array("apple", "pear")
order("total") = 3.75
order("paid") = True
order("note") = Null
Set customer = CreateObject("Dictionary")
customer("name") = "Ann ""the Amiga"" Smith"
Set order("customer") = customer

Print JsonStringify(order)
Print JsonStringify(order, 2)
