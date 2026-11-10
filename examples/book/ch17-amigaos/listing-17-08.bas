Option Explicit

Declare Sub Amiga2Date Lib "utility.library" Alias "#28" (ByVal date_amiga As Long, ByVal cd As Long)

' struct ClockData (utility/date.h)
Const CD_SEC = 0, CD_MIN = 2, CD_HOUR = 4, CD_MDAY = 6, CD_MONTH = 8, CD_YEAR = 10
Const CD_SIZE = 14

Sub Main()
    Dim cd As Long
    cd = AllocMem(CD_SIZE, True)
    Amiga2Date 86400& * 366 + 3600& * 13 + 60 * 5 + 9, cd     ' seconds since 1.1.1978
    Print PeekW(cd + CD_MDAY); "."; PeekW(cd + CD_MONTH); "."; PeekW(cd + CD_YEAR); _
          PeekW(cd + CD_HOUR); ":"; PeekW(cd + CD_MIN); ":"; PeekW(cd + CD_SEC)
    FreeMem cd
End Sub
