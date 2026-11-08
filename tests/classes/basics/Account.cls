Private mBalance As Currency
Private mOwner As String

Public Sub Init(ByVal owner As String, ByVal opening As Currency)
    mOwner = owner
    mBalance = opening
End Sub

Public Property Get Owner() As String
    Owner = mOwner
End Property

Public Property Get Balance() As Currency
    Balance = mBalance
End Property

Public Sub Deposit(ByVal amount As Currency)
    mBalance = mBalance + amount
End Sub

Public Function Withdraw(ByVal amount As Currency) As Boolean
    If amount > mBalance Then Exit Function
    mBalance = mBalance - amount
    Withdraw = True
End Function
