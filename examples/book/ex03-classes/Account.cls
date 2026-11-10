' Account.cls - a bank account: a class module (exercise 3 of the Boing BASIC manual).
' Every "New Account" is an object of its own, with its own owner, balance and limit.
Option Explicit

' The events an account raises. Whoever holds the account "WithEvents" can handle them.
Public Event Changed(ByVal amount As Currency, ByVal newBalance As Currency)
Public Event Overdrawn(ByVal amount As Currency, Cancel As Boolean)

' The object's own data. Private: only the class's code can touch it.
Private mNumber As Long
Private mOwner As String
Private mBalance As Currency
Private mLimit As Currency            ' how far below zero the balance may go

' Runs when the object is made (New): give it the next account number.
Private Sub Class_Initialize()
    lastNumber = lastNumber + 1       ' a Public variable of Main.bas, shared by all accounts
    mNumber = 1000 + lastNumber
End Sub

' Runs when the last reference to the object goes away.
Private Sub Class_Terminate()
    Print "(account"; mNumber; "closed)"
End Sub

' --- properties ---------------------------------------------------------------------------

' Read only: there is a Property Get but no Property Let.
Public Property Get Number() As Long
    Number = mNumber
End Property

Public Property Get Balance() As Currency
    Balance = mBalance
End Property

Public Property Get Owner() As String
    Owner = mOwner
End Property

' A Property Let can check the value before it keeps it.
Public Property Let Owner(ByVal value As String)
    If Trim(value) = "" Then Err.Raise 5, "Account", "An account needs an owner"
    mOwner = Trim(value)
End Property

Public Property Get Limit() As Currency
    Limit = mLimit
End Property

Public Property Let Limit(ByVal value As Currency)
    If value < 0 Then Err.Raise 5, "Account", "The limit can't be negative"
    mLimit = value
End Property

' --- methods ------------------------------------------------------------------------------

Public Sub Deposit(ByVal amount As Currency)
    If amount <= 0 Then Err.Raise 5, "Account", "Deposit a positive amount"
    mBalance = mBalance + amount
    RaiseEvent Changed(amount, mBalance)
End Sub

' Returns True if the money was paid out.
Public Function Withdraw(ByVal amount As Currency) As Boolean
    Dim cancel As Boolean
    If amount <= 0 Then Err.Raise 5, "Account", "Withdraw a positive amount"
    If mBalance - amount < -mLimit Then Exit Function      ' over the limit: never
    If mBalance - amount < 0 Then
        RaiseEvent Overdrawn(amount, cancel)                ' the handler may say no
        If cancel Then Exit Function
    End If
    mBalance = mBalance - amount
    RaiseEvent Changed(-amount, mBalance)
    Withdraw = True
End Function

' One line for a statement.
Public Function Summary() As String
    Summary = mNumber & "  " & Left(mOwner & Space(10), 10) & Right(Space(10) & Format(mBalance, "0.00"), 10)
End Function
