' Main.bas - uses the Account class (exercise 3 of the Boing BASIC manual).
' Run it with:   boing run Bank.bbp
Option Explicit

Public lastNumber As Long             ' the last account number given out (Account.cls)

Dim accounts As New Collection        ' every account, with its number as the key
Dim WithEvents current As Account     ' the account we work on: we get its events
Dim allowOverdraft As Boolean

Sub Main()
    Dim a As Account

    ' open three accounts
    OpenAccount "Ann", 0
    OpenAccount "Bob", 50
    OpenAccount "Cleo", 0

    ' an Owner that the Property Let refuses
    On Error Resume Next
    accounts(1).Owner = "   "
    Print "Rename: error"; Err.Number; "- "; Err.Description
    On Error GoTo 0

    Print
    Print "Working on Ann's account:"
    Set current = accounts("1001")
    current.Deposit 120
    If Not current.Withdraw(30.5) Then Print "  refused"
    If Not current.Withdraw(200) Then Print "  refused: over the limit"

    Print "Working on Bob's account:"
    Set current = accounts("1002")
    current.Deposit 20
    allowOverdraft = False
    If Not current.Withdraw(45) Then Print "  refused by the handler"
    allowOverdraft = True
    If Not current.Withdraw(45) Then Print "  refused by the handler"
    Set current = Nothing             ' no more events from here on

    Print
    Statement

    ' close Cleo's account: removing the last reference ends the object
    Print
    Set a = accounts("1003")
    accounts.Remove "1003"
    Print "Removed from the bank;"; accounts.Count; "accounts left"
    Set a = Nothing                   ' Class_Terminate runs now
    Print "Done."
End Sub

Sub OpenAccount(ByVal who As String, ByVal limit As Currency)
    Dim a As Account
    Set a = New Account               ' Class_Initialize runs here
    a.Owner = who
    a.Limit = limit
    accounts.Add a, CStr(a.Number)    ' the key must be a String
    Print "Opened account"; a.Number; "for "; a.Owner
End Sub

Sub Statement()
    Dim a As Account, total As Currency
    Print "No.   Owner        Balance"
    For Each a In accounts
        Print a.Summary()
        total = total + a.Balance
    Next
    Print "Total in the bank: "; Format(total, "0.00")
End Sub

' --- the events of "current" ----------------------------------------------------------------

Sub current_Changed(ByVal amount As Currency, ByVal newBalance As Currency)
    Print "  "; IIf(amount > 0, "in ", "out"); " "; Format(Abs(amount), "0.00"); ", balance now "; Format(newBalance, "0.00")
End Sub

Sub current_Overdrawn(ByVal amount As Currency, Cancel As Boolean)
    Print "  warning: taking "; Format(amount, "0.00"); " overdraws account"; current.Number
    If Not allowOverdraft Then Cancel = True
End Sub
