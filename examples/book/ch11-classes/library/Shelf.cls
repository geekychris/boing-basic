' Shelf.cls - a collection of books, kept by title
Option Explicit

Public Name As String
Private mBooks As New Collection

Public Function Add(ByVal title As String, ByVal year As Long) As Book
    Dim b As New Book
    b.Title = title
    b.Year = year
    Set b.Home = Me             ' Me: the Shelf object running this code
    mBooks.Add b, title         ' the title is the key
    Set Add = b
End Function

' a member called Item is the default: shelf("Dune") means shelf.Item("Dune")
Public Property Get Item(ByVal key As Variant) As Book
    Set Item = mBooks(key)
End Property

Public Property Get Count() As Long
    Count = mBooks.Count
End Property

Public Sub Remove(ByVal key As Variant)
    Dim b As Book
    Set b = mBooks(key)
    Set b.Home = Nothing        ' break the link back to the shelf
    mBooks.Remove key
End Sub

' For Each works on arrays and Collections, so hand out the Collection
Public Property Get Books() As Collection
    Set Books = mBooks
End Property

' the books point back at the shelf, so the shelf and its books keep each other alive:
' Clear breaks those links (and empties the shelf)
Public Sub Clear()
    Dim b As Book
    For Each b In mBooks
        Set b.Home = Nothing
    Next
    Set mBooks = New Collection
End Sub

Private Sub Class_Terminate()
    Print "shelf "; Name; " released"
End Sub
